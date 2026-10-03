/*****

 Проект «Ретро КР580» (https://github.com/chicherov/Retro80)
 Copyright © 2014-2020 Andrey Chicherov <chicherov@mac.com>

 *****/

int main(int argc, const char * argv[])
{
#ifdef GNUSTEP
	// Обозначения модификаторов в меню (GNUstep по умолчанию рисует ⌘ как «#», ⌥ как «+»).
	// Под GNUstep ⌘ — левый Alt, ⌥ — правый. Переопределяются через defaults write.
	@autoreleasepool
	{
		[NSUserDefaults.standardUserDefaults registerDefaults:@{
			@"GSCommandKeyString": @"Alt+",
			@"GSAlternateKeyString": @"RAlt+",
			@"GSShiftKeyString": @"Shift+",
			@"GSControlKeyString": @"Ctrl+"
		}];
	}
#endif

	return NSApplicationMain(argc, argv);
}
