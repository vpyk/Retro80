/*****

 Проект «Ретро КР580» (https://github.com/chicherov/Retro80)
 Copyright © 2014-2018 Andrey Chicherov <chicherov@mac.com>

 Скрытие пунктов меню под GNUstep

 Общее меню содержит пункты всех машин, а validateMenuItem: скрывает чужие через
 menuItem.hidden. В GNUstep у NSMenuItem нет скрытия, поэтому делегат каждого меню
 хранит полный список его пунктов и перед показом оставляет в меню только видимые.

 *****/

#import <objc/runtime.h>

#import "GNUstep-Menu.h"

static const void *hiddenKey = &hiddenKey;

@implementation NSMenuItem (GNUstep)

- (void)setHidden:(BOOL)hidden
{
	objc_setAssociatedObject(self, hiddenKey, hidden ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)hidden
{
	return objc_getAssociatedObject(self, hiddenKey) != nil;
}

@end

@implementation MenuHider
{
	NSArray<NSMenuItem *> *items;
	BOOL updating;
}

// NSMenu не удерживает делегата
static NSMutableArray<MenuHider *> *hiders;

+ (void)installInMenu:(NSMenu *)menu
{
	for (NSMenuItem *item in [menu.itemArray copy])
	{
		// Пункты macOS для других приложений, в GNUstep не работают
		if (item.action == @selector(hideOtherApplications:) || item.action == @selector(unhideAllApplications:))
			item.hidden = YES;

		if (item.submenu)
			[self installInSubmenu:item.submenu];
	}
}

+ (void)installInSubmenu:(NSMenu *)menu
{
	// Меню, которые наполняет GNUstep: службы, окна, недавние документы
	if (menu == NSApp.servicesMenu || menu == NSApp.windowsMenu || menu.delegate)
		return;

	for (NSMenuItem *item in [menu.itemArray copy])
		if (item.action == @selector(clearRecentDocuments:))
			return;

	[self installInMenu:menu];

	// Копия: в GNUstep itemArray — это сам изменяемый массив пунктов меню
	MenuHider *hider = [[MenuHider alloc] init];
	hider->items = [menu.itemArray copy];

	if (hiders == nil)
		hiders = [NSMutableArray array];

	[hiders addObject:hider];
	menu.delegate = hider;
}

// Все пункты меню, включая убранные из него
static NSArray<NSMenuItem *> *allItems(NSMenu *menu)
{
	if ([menu.delegate isKindOfClass:MenuHider.class])
		return ((MenuHider *) menu.delegate)->items;

	return [menu.itemArray copy];
}

static BOOL isHidden(NSMenuItem *item)
{
	if (item.isSeparatorItem)
		return NO;

	// Как в macOS: пункт с подменю скрыт, если скрыты все пункты подменю
	if (item.submenu)
	{
		for (NSMenuItem *subitem in allItems(item.submenu))
			if (!subitem.isSeparatorItem && !isHidden(subitem))
				return NO;

		return YES;
	}

	// Проверка пункта тем же обработчиком, что выбирает GNUstep
	if (item.action)
	{
		id validator = [NSApp targetForAction:item.action to:item.target from:item];

		if ([validator respondsToSelector:@selector(validateMenuItem:)])
			[validator validateMenuItem:item];
	}

	return item.hidden;
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
	// Изменение меню в GNUstep само может вызвать его обновление, а с ним и этот метод
	if (updating)
		return;

	updating = YES;
	[self updateMenu:menu];
	updating = NO;
}

- (void)updateMenu:(NSMenu *)menu
{
	NSMutableArray<NSMenuItem *> *visible = [NSMutableArray arrayWithCapacity:items.count];

	for (NSMenuItem *item in items)
	{
		if (isHidden(item))
			continue;

		// Без разделителей в начале и подряд
		if (item.isSeparatorItem && (visible.count == 0 || visible.lastObject.isSeparatorItem))
			continue;

		[visible addObject:item];
	}

	// ... и в конце
	while (visible.lastObject.isSeparatorItem)
		[visible removeLastObject];

	if ([visible isEqualToArray:menu.itemArray])
		return;

	// Уведомления об изменении меню — одним разом после перестройки, как в -[NSMenu update]
	[menu setMenuChangedMessagesEnabled:NO];

	while (menu.numberOfItems)
		[menu removeItemAtIndex:menu.numberOfItems - 1];

	for (NSMenuItem *item in visible)
		[menu addItem:item];

	[menu setMenuChangedMessagesEnabled:YES];
}

@end
