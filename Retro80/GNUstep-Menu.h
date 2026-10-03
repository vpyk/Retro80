/*****

 Проект «Ретро КР580» (https://github.com/chicherov/Retro80)
 Copyright © 2014-2018 Andrey Chicherov <chicherov@mac.com>

 Скрытие пунктов меню под GNUstep

 *****/

// Без <NSMenuDelegate>: в GNUstep все его методы обязательные, а нужен только menuNeedsUpdate:
@interface MenuHider : NSObject

// Подключить скрытие пунктов ко всем подменю (кроме тех, что наполняет GNUstep)
+ (void)installInMenu:(NSMenu *)menu;

@end
