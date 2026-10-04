/*****

 Проект «Ретро КР580» (https://github.com/chicherov/Retro80)
 Copyright © 2014-2020 Andrey Chicherov <chicherov@mac.com>

 *****/

int main(int argc, const char * argv[])
{
#ifdef GNUSTEP
	// Обозначения модификаторов в меню (GNUstep по умолчанию рисует ⌘ как «#», ⌥ как «+»).
	// Под X11 ⌘ — левый Alt, ⌥ — правый; под Windows ⌘ — левый Ctrl, ⌥ — Alt, Control — правый Ctrl.
	// Переопределяются через defaults write.
	@autoreleasepool
	{
		[NSUserDefaults.standardUserDefaults registerDefaults:@{
#ifdef _WIN32
			@"GSCommandKeyString": @"Ctrl+",
			@"GSAlternateKeyString": @"Alt+",
			@"GSControlKeyString": @"RCtrl+",
#else
			@"GSCommandKeyString": @"Alt+",
			@"GSAlternateKeyString": @"RAlt+",
			@"GSControlKeyString": @"Ctrl+",
#endif
			@"GSShiftKeyString": @"Shift+"
		}];
	}
#endif

	return NSApplicationMain(argc, argv);
}
