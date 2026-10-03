/*****

 Проект «Ретро КР580» (https://github.com/chicherov/Retro80)
 Copyright © 2014-2018 Andrey Chicherov <chicherov@mac.com>

 Поддержка звукового ввода/вывода через miniaudio (GNUstep)

 Как и Sound.m на macOS, звук тактирует эмуляцию: на каждый буфер устройства
 вывода эмуляция выполняется ровно на его длительность и заполняет буфер звуком.

 *****/

#import "Computer.h"
#import "Sound.h"
#import "miniaudio.h"

#define SAMPLE_RATE		48000
#define CHANNELS		2
#define PERIOD_FRAMES	(SAMPLE_RATE/50)

@implementation Sound
{
	ma_device device;
	BOOL deviceStarted;
	BOOL threadRegistered;
	NSTimer *keepAlive;

	ma_decoder inAudioFile;
	BOOL isInput;
	ma_uint64 inAudioFilePos;
	ma_uint64 inAudioFileLength;
	BOOL pause;

	ma_encoder outAudioFile;
	BOOL isOutput;
	ma_uint64 outAudioFilePos;
	ma_uint64 outAudioFileLength;

	unsigned quartz;
	uint64_t frame;

	// Буфер, который заполняет эмуляция; отдаётся устройству, когда эмуляция дошла до его конца
	int16_t *audioBuffer;
	ma_uint32 audioBufferFrames;
	BOOL audioBufferPending;

	int16_t *audioBufferPtr;
	unsigned audioBufferSize;

	int16_t snd_l, snd_r;
	unsigned lastIndex;

	int32_t s1_l, s1_r;
	int32_t s2_l, s2_r;
}

@synthesize computer;
@synthesize textField;

static uint32_t filter_diff[2][64] = {
	0x0000, 0x0034, 0x0069, 0x00A1, 0x00DB, 0x0118, 0x015A, 0x01A2,
	0x01EF, 0x0244, 0x02A0, 0x0305, 0x0374, 0x03EE, 0x0474, 0x0506,
	0x05A5, 0x0653, 0x0711, 0x07DE, 0x08BC, 0x09AC, 0x0AAF, 0x0BC5,
	0x0CEF, 0x0E2D, 0x0F81, 0x10EB, 0x126B, 0x1402, 0x15B0, 0x1776,
	0x1953, 0x1B49, 0x1D57, 0x1F7E, 0x21BC, 0x2414, 0x2684, 0x290B,
	0x2BAB, 0x2E63, 0x3131, 0x3417, 0x3713, 0x3A24, 0x3D4B, 0x4086,
	0x43D5, 0x4737, 0x4AAA, 0x4E2F, 0x51C4, 0x5567, 0x5919, 0x5CD7,
	0x60A2, 0x6476, 0x6854, 0x6C39, 0x7026, 0x7418, 0x780D, 0x7C06,
	0x8000, 0x83F9, 0x87F2, 0x8BE7, 0x8FD9, 0x93C6, 0x97AB, 0x9B89,
	0x9F5D, 0xA328, 0xA6E6, 0xAA98, 0xAE3B, 0xB1D0, 0xB555, 0xB8C8,
	0xBC2A, 0xBF79, 0xC2B4, 0xC5DB, 0xC8EC, 0xCBE8, 0xCECE, 0xD19C,
	0xD454, 0xD6F4, 0xD97B, 0xDBEB, 0xDE43, 0xE081, 0xE2A8, 0xE4B6,
	0xE6AC, 0xE889, 0xEA4F, 0xEBFD, 0xED94, 0xEF14, 0xF07E, 0xF1D2,
	0xF310, 0xF43A, 0xF550, 0xF653, 0xF743, 0xF821, 0xF8EE, 0xF9AC,
	0xFA5A, 0xFAF9, 0xFB8B, 0xFC11, 0xFC8B, 0xFCFA, 0xFD5F, 0xFDBB,
	0xFE10, 0xFE5D, 0xFEA5, 0xFEE7, 0xFF24, 0xFF5E, 0xFF96, 0xFFCB
};

static NSString *timeString(ma_uint64 frames)
{
	return [NSString stringWithFormat:@"%02u:%02u",
									  (unsigned) (frames/SAMPLE_RATE)/60,
									  (unsigned) (frames/SAMPLE_RATE)%60];
}

- (NSString *)inputTimeString
{
	return [NSString stringWithFormat:@"%@/%@", timeString(inAudioFilePos), timeString(inAudioFileLength)];
}

- (void)setStatus:(NSString *)string
{
	[textField performSelectorOnMainThread:@selector(setStringValue:) withObject:string waitUntilDone:NO];
}

- (void)closeInput
{
	if (isInput)
		ma_decoder_uninit(&inAudioFile);

	isInput = NO;
}

- (void)closeOutput
{
	if (isOutput)
		ma_encoder_uninit(&outAudioFile);

	isOutput = NO;
}

// Запись сгенерированного буфера в WAV. Тишина до первого сигнала не пишется,
// паузы между сигналами сокращаются до 3 секунд.
- (void)writeOutput
{
	int16_t *ptr = audioBuffer;
	ma_uint32 count = audioBufferFrames*CHANNELS;

	for (int16_t v = *ptr; --count && *++ptr == v;);

	if (count)
	{
		ma_uint64 silence = MIN(outAudioFileLength - outAudioFilePos, SAMPLE_RATE*3);

		if (silence)
		{
			NSMutableData *zero = [NSMutableData dataWithLength:(NSUInteger) silence*CHANNELS*sizeof(int16_t)];
			ma_encoder_write_pcm_frames(&outAudioFile, zero.bytes, silence, NULL);
			outAudioFileLength = outAudioFilePos += silence;
		}

		ma_encoder_write_pcm_frames(&outAudioFile, audioBuffer, audioBufferFrames, NULL);
		outAudioFileLength = outAudioFilePos += audioBufferFrames;

		[self setStatus:timeString(outAudioFileLength)];
	}

	else if (outAudioFileLength)
		outAudioFileLength += audioBufferFrames;
}

- (void)render:(int16_t *)output frames:(ma_uint32)frameCount
{
	memset(output, 0, frameCount*CHANNELS*sizeof(int16_t));

	@synchronized(computer)
	{
		if (frame == (uint64_t) -1)
			return;

		// Новый буфер; если эмуляция не дошла до конца прошлого, он заполняется дальше
		if (!audioBufferPending)
		{
			if (audioBufferFrames != frameCount)
			{
				free(audioBuffer);
				audioBuffer = malloc(frameCount*CHANNELS*sizeof(int16_t));
				audioBufferFrames = frameCount;
			}

			memset(audioBuffer, 0, frameCount*CHANNELS*sizeof(int16_t));

			if (isInput && !pause)
			{
				ma_uint64 framesRead = 0;
				ma_decoder_read_pcm_frames(&inAudioFile, audioBuffer, frameCount, &framesRead);

				if (framesRead)
				{
					inAudioFilePos += framesRead;
					[self setStatus:self.inputTimeString];
				}
				else
				{
					[self closeInput];
					[self setStatus:@"--:--"];
				}
			}

			audioBufferPtr = audioBuffer;
			audioBufferSize = audioBufferFrames;
			audioBufferPending = YES;

			lastIndex &= 63;
		}

		uint64_t interval = ((uint64_t) quartz*audioBufferFrames)/SAMPLE_RATE;

		if (![computer execute:frame + interval])
			return;

		[self flush:frame + interval];

		if (isOutput)
			[self writeOutput];

		memcpy(output, audioBuffer, MIN(frameCount, audioBufferFrames)*CHANNELS*sizeof(int16_t));

		audioBufferPending = NO;
		frame += interval;
	}
}

static void dataCallback(ma_device *pDevice, void *pOutput, const void *pInput, ma_uint32 frameCount)
{
	Sound *sound = (__bridge Sound *) pDevice->pUserData;

	// Поток miniaudio создан не через NSThread
	if (!sound->threadRegistered)
	{
		GSRegisterCurrentThread();
		sound->threadRegistered = YES;
	}

	@autoreleasepool
	{
		[sound render:pOutput frames:frameCount];
	}
}

- (BOOL)input:(uint64_t)clock
{
	if (!audioBufferPending || !isInput)
		return NO;

	ma_uint64 index = ((clock - frame)*SAMPLE_RATE)/quartz;

	if (index >= audioBufferFrames)
		index = audioBufferFrames - 1;

	return audioBuffer[index*CHANNELS] < 0;
}

- (void)flush:(uint64_t)clock
{
	if (isInput || !audioBufferPending)
		return;

	unsigned index = (unsigned) (((clock - frame)*SAMPLE_RATE*64)/quartz);

	if (index == lastIndex)
		return;

	uint32_t scale;

	if (((index ^ lastIndex) & ~63) == 0)
	{
		scale = filter_diff[1][index & 63] - filter_diff[1][lastIndex & 63];
		s2_l += snd_l*scale;
		s2_r += snd_r*scale;

		scale = filter_diff[0][index & 63] - filter_diff[0][lastIndex & 63];
		s1_l += snd_l*scale;
		s1_r += snd_r*scale;
	}
	else
	{
		scale = 0x10000 - filter_diff[1][lastIndex & 63];
		uint16_t l = (snd_l*scale + s2_l) >> 16;
		uint16_t r = (snd_l*scale + s2_r) >> 16;

		scale = 0x8000 - filter_diff[0][lastIndex & 63];
		s2_l = s1_l + snd_l*scale;
		s2_r = s1_r + snd_r*scale;

		if (audioBufferSize)
		{
			*audioBufferPtr++ = l;
			*audioBufferPtr++ = r;
			--audioBufferSize;
		}

		lastIndex |= 63;
		lastIndex++;

		uint32_t val_l = snd_l*0x8000;
		uint32_t val_r = snd_r*0x8000;

		while ((index ^ lastIndex) & ~63)
		{
			l = (s2_l + val_l) >> 16;
			r = (s2_r + val_r) >> 16;

			if (audioBufferSize)
			{
				*audioBufferPtr++ = l;
				*audioBufferPtr++ = r;
				--audioBufferSize;
			}

			lastIndex += 64;
			s2_l = val_l;
			s2_r = val_r;
		}

		scale = filter_diff[1][index & 63] - 0x8000;
		s2_l += snd_l*scale;
		s2_r += snd_r*scale;

		scale = filter_diff[0][index & 63];
		s1_l = snd_l*scale;
		s1_r = snd_r*scale;
	}

	lastIndex = index;
}

- (void)update:(uint64_t)clock output:(BOOL)output left:(int16_t)left right:(int16_t)right
{
	if (isOutput)
		left = right = output ? 20000 : -20000;

	if (snd_l ^ left || snd_r ^ right)
	{
		[self flush:clock];

		snd_l = left;
		snd_r = right;
	}
}

- (void)openWave:(NSURL *)URL
{
	@synchronized(computer)
	{
		[self closeOutput];
		[self closeInput];

		// Декодер сам приводит файл к формату устройства
		ma_decoder_config config = ma_decoder_config_init(ma_format_s16, CHANNELS, SAMPLE_RATE);
		config.encodingFormat = ma_encoding_format_wav;

		ma_result result = ma_decoder_init_file(URL.path.fileSystemRepresentation, &config, &inAudioFile);

		if (result != MA_SUCCESS)
		{
			NSLog(@"ma_decoder_init_file error: %s", ma_result_description(result));
			return;
		}

		if (ma_decoder_get_length_in_pcm_frames(&inAudioFile, &inAudioFileLength) != MA_SUCCESS)
			inAudioFileLength = 0;

		isInput = YES;
		inAudioFilePos = 0;
		pause = NO;

		textField.textColor = [NSColor blackColor];
		textField.stringValue = self.inputTimeString;
	}
}

- (void)keepAlive:(NSTimer *)timer
{
}

- (BOOL)start
{
	dispatch_async(dispatch_get_main_queue(), ^{
		self->textField.textColor = [NSColor blackColor];
		self->textField.stringValue = @"--:--";
	});

	quartz = self.computer.quartz;
	frame = self.computer.clock;
	audioBufferPending = NO;
	threadRegistered = NO;

	ma_device_config config = ma_device_config_init(ma_device_type_playback);
	config.playback.format = ma_format_s16;
	config.playback.channels = CHANNELS;
	config.sampleRate = SAMPLE_RATE;
	config.periodSizeInFrames = PERIOD_FRAMES;
	config.periods = 3;
	config.dataCallback = dataCallback;
	config.pUserData = (__bridge void *) self;

	ma_result result = ma_device_init(NULL, &config, &device);

	if (result != MA_SUCCESS)
	{
		NSLog(@"ma_device_init error: %s", ma_result_description(result));
		return NO;
	}

	if ((result = ma_device_start(&device)) != MA_SUCCESS)
	{
		NSLog(@"ma_device_start error: %s", ma_result_description(result));
		ma_device_uninit(&device);
		return NO;
	}

	deviceStarted = YES;

	// Звук вызывается из потока miniaudio, а поток эмуляции (Computer -thread) должен жить,
	// пока работает звук: его цикл выполнения завершается, когда в нём не остаётся источников.
	keepAlive = [NSTimer scheduledTimerWithTimeInterval:1.0
												 target:self
											   selector:@selector(keepAlive:)
											   userInfo:nil
												repeats:YES];

#ifdef DEBUG
	NSLog(@"Sound start: %s", ma_get_backend_name(device.pContext->backend));
#endif

	return YES;
}

- (void)stop
{
	@synchronized(computer)
	{
		frame = -1;
	}

	// Без блокировки: ma_device_uninit ждёт завершения текущего вызова dataCallback
	if (deviceStarted)
		ma_device_uninit(&device);

	deviceStarted = NO;

	[keepAlive invalidate];
	keepAlive = nil;

	[self closeOutput];
	[self closeInput];

	textField.stringValue = @"";

#ifdef DEBUG
	NSLog(@"Sound stop");
#endif
}

- (BOOL)isOutput
{
	return isOutput;
}

- (BOOL)isInput
{
	return isInput;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if (menuItem.action == @selector(tape_play:))
	{
		if (isInput)
			menuItem.title = pause ? @"Возобновить" : @"Пауза";
		else
			menuItem.title = @"Воспроизвести";

		return YES;
	}

	if (menuItem.action == @selector(tape_stop:))
		return isInput;

	if (menuItem.action == @selector(tape_backward:))
		return isInput;

	if (menuItem.action == @selector(tape_forward:))
		return isInput;

	if (menuItem.action == @selector(tape_record:))
	{
		menuItem.state = isOutput;
		return !isInput;
	}

	return NO;
}

- (IBAction)tape_play:(id)sender
{
	if (!isInput)
	{
		NSOpenPanel *panel = [NSOpenPanel openPanel];
		panel.allowedFileTypes = @[@"wav"];

		if ([panel runModal] == NSModalResponseOK && panel.URLs.count == 1)
			[self openWave:panel.URLs.firstObject];
	}
	else
	{
		pause = !pause;
	}
}

- (IBAction)tape_stop:(id)sender
{
	@synchronized(computer)
	{
		[self closeOutput];
		[self closeInput];

		textField.textColor = [NSColor blackColor];
		textField.stringValue = @"--:--";
	}
}

- (void)seekInput:(int64_t)frames
{
	@synchronized(computer)
	{
		if (isInput)
		{
			if (frames < 0)
				inAudioFilePos = inAudioFilePos >= (ma_uint64) -frames ? inAudioFilePos + frames : 0;
			else if (inAudioFilePos + frames < inAudioFileLength)
				inAudioFilePos += frames;

			ma_decoder_seek_to_pcm_frame(&inAudioFile, inAudioFilePos);
			textField.stringValue = self.inputTimeString;
		}
	}
}

- (IBAction)tape_backward:(id)sender
{
	[self seekInput:-SAMPLE_RATE];
}

- (IBAction)tape_forward:(id)sender
{
	[self seekInput:SAMPLE_RATE];
}

- (IBAction)tape_record:(id)sender
{
	if (isOutput)
	{
		@synchronized(computer)
		{
			[self closeOutput];

			textField.textColor = [NSColor blackColor];
			textField.stringValue = @"--:--";
		}
	}
	else if (!isInput)
	{
		NSSavePanel *savePanel = [NSSavePanel savePanel];
		savePanel.allowedFileTypes = @[@"wav"];

		if ([savePanel runModal] == NSModalResponseOK)
		{
			@synchronized(computer)
			{
				ma_encoder_config config = ma_encoder_config_init(ma_encoding_format_wav, ma_format_s16, CHANNELS, SAMPLE_RATE);
				ma_result result = ma_encoder_init_file(savePanel.URL.path.fileSystemRepresentation, &config, &outAudioFile);

				if (result != MA_SUCCESS)
				{
					NSLog(@"ma_encoder_init_file error: %s", ma_result_description(result));
				}
				else
				{
					isOutput = YES;

					textField.textColor = [NSColor redColor];
					textField.stringValue = @"--:--";

					outAudioFilePos = 0;
					outAudioFileLength = 0;
				}
			}
		}
	}
}

- (void)awakeFromNib
{
	// В Document.xib ширину счётчика задаёт автораскладка macOS, GNUstep её не применяет
	textField.translatesAutoresizingMaskIntoConstraints = YES;
	textField.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
	textField.frame = NSMakeRect(5, 0, 120, 22);
}

- (void)dealloc
{
#ifdef DEBUG
	NSLog(@"%@ dealloc", NSStringFromClass(self.class));
#endif

	free(audioBuffer);
}

@end
