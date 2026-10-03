#import <objc/runtime.h>

@implementation NSLayoutConstraint (GNUstep)
- (void)setConstant:(CGFloat)constant { }
@end

@implementation NSMenuItem (GNUstep)
- (void)setHidden:(BOOL)hidden {}
- (BOOL)hidden { return NO; }
@end

@implementation NSDocument (GNUstep)
- (BOOL)inViewingMode { return NO; }
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
