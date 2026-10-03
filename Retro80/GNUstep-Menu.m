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
	NSMenu *managedMenu;
	NSArray<NSMenuItem *> *items;
	BOOL updating;
	BOOL scheduled;
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
	hider->managedMenu = menu;

	if (hiders == nil)
	{
		hiders = [NSMutableArray array];

		// Состав меню, а с ним и сочетания клавиш, должен следовать за машиной в главном окне,
		// даже если меню не открывали. Только главное окно: диалоги (сохранение и т.п.) им не
		// становятся, а перестройка меню при их открытии ломала обновление «Открыть недавние».
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(windowDidChange:)
												   name:NSWindowDidBecomeMainNotification
												 object:nil];
	}

	[hiders addObject:hider];
	menu.delegate = hider;
}

+ (void)windowDidChange:(NSNotification *)notification
{
	for (MenuHider *hider in hiders)
		[hider scheduleUpdate];
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

// Показано ли меню (внутренний метод GNUstep; если его нет, считаем показанным)
static BOOL isVisible(NSMenu *menu)
{
	SEL selector = NSSelectorFromString(@"_isVisible");

	if (![menu respondsToSelector:selector])
		return YES;

	BOOL (*imp)(id, SEL) = (BOOL (*)(id, SEL)) [menu methodForSelector:selector];
	return imp(menu, selector);
}

// GNUstep вызывает этот метод из -[NSMenu update]. Для показанного меню перестраивать его
// можно сразу. Скрытое меню обновляется из -[NSMenu performKeyEquivalent:], который
// запоминает число пунктов до обновления и перебирает их после: там меню менять нельзя,
// перестройка откладывается до следующего прохода цикла событий.
- (void)menuNeedsUpdate:(NSMenu *)aMenu
{
	if (isVisible(aMenu))
		[self updateNow];
	else
		[self scheduleUpdate];
}

- (void)scheduleUpdate
{
	if (scheduled)
		return;

	scheduled = YES;

	// Не в NSEventTrackingRunLoopMode: пока пользователь ведёт мышью по меню, оно не меняется
	[self performSelector:@selector(scheduledUpdate)
			   withObject:nil
			   afterDelay:0
				  inModes:@[NSDefaultRunLoopMode, NSModalPanelRunLoopMode]];
}

- (void)scheduledUpdate
{
	scheduled = NO;
	[self updateNow];
}

- (void)updateNow
{
	// Изменение меню в GNUstep само может вызвать его обновление, а с ним и этот метод
	if (updating)
		return;

	updating = YES;
	[self updateMenu];
	updating = NO;
}

- (void)updateMenu
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

	if ([visible isEqualToArray:managedMenu.itemArray])
		return;

	// Уведомления об изменении меню — одним разом после перестройки, как в -[NSMenu update]
	[managedMenu setMenuChangedMessagesEnabled:NO];

	// Меняются только пункты, которые скрываются или появляются: пункт, удалённый и снова
	// добавленный в меню, в GNUstep перестаёт показывать изменения своего подменю
	// («Открыть недавние»). Порядок пунктов в меню и в visible одинаковый, как в items.
	for (NSInteger index = managedMenu.numberOfItems - 1; index >= 0; index--)
		if (![visible containsObject:[managedMenu itemAtIndex:index]])
			[managedMenu removeItemAtIndex:index];

	for (NSInteger index = 0; index < (NSInteger) visible.count; index++)
		if (index >= managedMenu.numberOfItems || [managedMenu itemAtIndex:index] != visible[index])
			[managedMenu insertItem:visible[index] atIndex:index];

	[managedMenu setMenuChangedMessagesEnabled:YES];
}

@end
