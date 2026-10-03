#import <objc/runtime.h>

@implementation NSLayoutConstraint (GNUstep)
- (void)setConstant:(CGFloat)constant { }
@end

@implementation NSDocument (GNUstep)
- (BOOL)inViewingMode { return NO; }
@end

// Строка сочетания клавиш в меню. GNUstep не показывает сочетания с функциональными
// клавишами (стрелки, F1…), а остальные рисует как «#r». Здесь строка строится заново:
// «Alt+R», «Alt+Shift+S», «RAlt+Alt+R», «Alt+→», «Alt+F1». Обозначения модификаторов —
// настройки GNUstep GS*KeyString (значения по умолчанию задаются в main.m).
// _keyEquivalentString — внутренний метод NSMenuItemCell; если его нет, остаётся вид GNUstep.

@interface NSMenuItemCell (Retro80)
- (NSString *)retro80_keyEquivalentString;
@end

@implementation NSMenuItemCell (Retro80)

+ (void)load
{
	Method original = class_getInstanceMethod(self, NSSelectorFromString(@"_keyEquivalentString"));

	if (original)
		method_exchangeImplementations(original, class_getInstanceMethod(self, @selector(retro80_keyEquivalentString)));
}

static NSString *keyEquivalentName(NSString *key)
{
	unichar ch = [key characterAtIndex:0];

	switch (ch)
	{
		case NSUpArrowFunctionKey:
			return @"↑";

		case NSDownArrowFunctionKey:
			return @"↓";

		case NSLeftArrowFunctionKey:
			return @"←";

		case NSRightArrowFunctionKey:
			return @"→";
	}

	if (ch >= NSF1FunctionKey && ch <= NSF35FunctionKey)
		return [NSString stringWithFormat:@"F%d", ch - NSF1FunctionKey + 1];

	return ch >= 0xF700 ? nil : key.uppercaseString;
}

static void appendModifier(NSMutableString *string, NSString *name)
{
	[string appendString:[NSUserDefaults.standardUserDefaults stringForKey:name] ?: @""];
}

- (NSString *)retro80_keyEquivalentString
{
	NSMenuItem *menuItem = self.menuItem;
	NSString *key = menuItem.keyEquivalent;

	if (key.length == 0)
		return key;

	NSString *name = keyEquivalentName(key);

	if (name == nil)
		return nil;

	NSUInteger mask = menuItem.keyEquivalentModifierMask;
	NSMutableString *string = [NSMutableString string];

	if (mask & NSEventModifierFlagControl)
		appendModifier(string, @"GSControlKeyString");

	if (mask & NSEventModifierFlagOption)
		appendModifier(string, @"GSAlternateKeyString");

	if (mask & NSEventModifierFlagCommand)
		appendModifier(string, @"GSCommandKeyString");

	// Заглавная буква в сочетании означает Shift
	if ((mask & NSEventModifierFlagShift) || ![key isEqualToString:key.lowercaseString])
		appendModifier(string, @"GSShiftKeyString");

	[string appendString:name];
	return string;
}

@end

// В GNUstep фильтр расширений в диалогах открытия и сохранения учитывает регистр,
// а файлы эмулируемых машин часто называются заглавными буквами (.RK, .RKA и т.п.).
// Через setAllowedFileTypes: проходят все диалоги, включая открытие документа:
// к каждому расширению добавляется его вариант в верхнем регистре.

@interface NSSavePanel (Retro80)
- (void)retro80_setAllowedFileTypes:(NSArray<NSString *> *)types;
@end

@implementation NSSavePanel (Retro80)

+ (void)load
{
	method_exchangeImplementations(class_getInstanceMethod(self, @selector(setAllowedFileTypes:)),
								   class_getInstanceMethod(self, @selector(retro80_setAllowedFileTypes:)));
}

- (void)retro80_setAllowedFileTypes:(NSArray<NSString *> *)types
{
	NSMutableArray<NSString *> *allTypes = nil;

	if (types)
	{
		allTypes = [NSMutableArray arrayWithArray:types];

		for (NSString *type in types)
			if (![allTypes containsObject:type.uppercaseString])
				[allTypes addObject:type.uppercaseString];
	}

	// После обмена реализаций это вызов исходного setAllowedFileTypes:
	[self retro80_setAllowedFileTypes:allTypes];
}

@end
