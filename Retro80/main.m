/*****

 Проект «Ретро КР580» (https://github.com/chicherov/Retro80)
 Copyright © 2014-2020 Andrey Chicherov <chicherov@mac.com>

 *****/

int main(int argc, const char * argv[])
{
#ifdef GNUSTEP
	// Модификаторы и их обозначения в меню (GNUstep по умолчанию рисует ⌘ как «#», ⌥ как «+»).
	// Под X11 ⌘ — левый Alt, ⌥ — правый Alt (РУС/ЛАТ), Control — Ctrl.
	// Под Windows сервер GNUstep не различает левый и правый Alt, поэтому как в X11 по возможности:
	// ⌘ — Alt, Control — левый Ctrl ([УС]), ⌥ — правый Ctrl (РУС/ЛАТ); по умолчанию было бы
	// ⌘ — левый Ctrl, ⌥ — Alt. Всё переопределяется через defaults write.
	@autoreleasepool
	{
		[NSUserDefaults.standardUserDefaults registerDefaults:@{
#ifdef _WIN32
			@"GSFirstCommandKey": @"Alt_R",
			@"GSFirstControlKey": @"Control_L",
			@"GSFirstAlternateKey": @"Control_R",
			@"GSCommandKeyString": @"Alt+",
			@"GSAlternateKeyString": @"RCtrl+",
			@"GSControlKeyString": @"Ctrl+",
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
