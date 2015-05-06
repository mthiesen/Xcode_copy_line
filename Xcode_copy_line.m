// The MIT License (MIT)
//
// Copyright (c) 2014 Malte Thiesen
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

// -----------------------------------------------------------------------------
// Pasteboard helpers
// -----------------------------------------------------------------------------

static id fullLinePasteboardItem = nil;

static void rememberCopiedPasteboardItem() {
    fullLinePasteboardItem = nil;
    if ([[NSPasteboard generalPasteboard] pasteboardItems].count == 1)
        fullLinePasteboardItem = [[[NSPasteboard generalPasteboard] pasteboardItems] objectAtIndex:0];
}

static BOOL isPasteboardItemFullLine() {
    if ([[NSPasteboard generalPasteboard] pasteboardItems].count == 1)
        return [[[NSPasteboard generalPasteboard] pasteboardItems] objectAtIndex:0] == fullLinePasteboardItem;
    else
        return NO;
}

// -----------------------------------------------------------------------------
// NSTextView extensions
// -----------------------------------------------------------------------------

@implementation NSTextView (XcodeCopyLineExtensions)

// Returns the column the cursor currently is on.
- (NSUInteger)xcl_cursorColumn {
    const NSUInteger beginningOfCurrentLine = [[self string] lineRangeForRange:[self selectedRange]].location;
    const NSUInteger cursorColumn = MAX(self.selectedRange.location - beginningOfCurrentLine, 0);
    return cursorColumn;
}

// Places the cursor an a specified colum in the current line.
// If the line is too short the cursor is placed at the end of the line.
- (void)xcl_setCursorColumn:(NSUInteger)column {
    const NSRange lineRange = [[self string] lineRangeForRange:[self selectedRange]];
    const NSUInteger lastCharacterOnLinePos = MAX(lineRange.location + lineRange.length - 1, lineRange.location);
    const NSUInteger newCursorPos = MIN(lineRange.location + column, lastCharacterOnLinePos);
    const NSRange newSelection = NSMakeRange(newCursorPos, 0);
    
    [self setSelectedRange:newSelection];
    [self scrollRangeToVisible:newSelection];
}

// If this is called at the beginning of an undo group the current cursor position
// is restored if the undo group is undone.
- (void)xcl_markCursorPositionForUndo {
    // The cursor position is normally not considered when an undo is perfomed.
    // We force the desired behaviour by inserting a dummy character an deleting
    // it immediately afterwards.
    [self insertText:@"x"];
    [self doCommandBySelector:@selector(deleteBackward:)];
}

@end

// -----------------------------------------------------------------------------
// DVTSourceTextView hooks
// -----------------------------------------------------------------------------

static NSMenuItem * cutMenuItem = nil;
static NSMenuItem * copyMenuItem = nil;
static NSTextView * activeTextView = nil;
static BOOL performingHookedCommand = NO;

typedef BOOL (*DVTSourceTextViewResponderMethodPtr)(id, SEL);
typedef void (*DVTSourceTextViewEditMethodPtr)(id, SEL, id);

static DVTSourceTextViewResponderMethodPtr originalBecomeFirstResponderMethod = NULL;
static BOOL becomeFirstResponderHook(id self_, SEL selector) {
    activeTextView = self_;
    
    // Enable the Cut and Copy menu items in case they were disabled.
    [cutMenuItem setEnabled:YES];
    [copyMenuItem setEnabled:YES];
    
    return originalBecomeFirstResponderMethod(self_, selector);
}

static DVTSourceTextViewResponderMethodPtr originalResignFirstResponderMethod = NULL;
static BOOL resignFirstResponderHook(id self_, SEL selector) {
    activeTextView = nil;
    return originalResignFirstResponderMethod(self_, selector);
}

static DVTSourceTextViewEditMethodPtr originalCutMethod = NULL;
static void cutHook(id self_, SEL selector, id sender) {
    NSTextView * self = (NSTextView *)self_;
    
    if (self.selectedRange.length == 0 && !performingHookedCommand) {
        performingHookedCommand = YES;
        
        const NSUInteger cursorColumn = [self xcl_cursorColumn];
        
        // Cut the current line.
        [self.undoManager beginUndoGrouping];
        [self xcl_markCursorPositionForUndo];
        [self doCommandBySelector:@selector(selectLine:)];
        [self doCommandBySelector:@selector(cut:)];
        [self.undoManager endUndoGrouping];
        
        // Place the cursor on the same column as before on the line below the cut one.
        [self xcl_setCursorColumn:cursorColumn];
        
        // Remember the item that was placed in the NSUndoManager.
        // If this item is pasted we need to perform a special full line paste.
        rememberCopiedPasteboardItem();
        
        performingHookedCommand = NO;
    } else if (self.selectedRange.length > 0) {
        originalCutMethod(self_, selector, sender);
        fullLinePasteboardItem = nil;
    }
}

static DVTSourceTextViewEditMethodPtr originalCopyMethod = NULL;
static void copyHook(id self_, SEL selector, id sender) {
    NSTextView * self = (NSTextView *)self_;
    
    if (self.selectedRange.length == 0 && !performingHookedCommand) {
        performingHookedCommand = YES;
        
        // Copy the current line.
        const NSUInteger cursorPos = self.selectedRange.location;
        [self doCommandBySelector:@selector(selectLine:)];
        [self doCommandBySelector:@selector(copy:)];
        [self setSelectedRange:NSMakeRange(cursorPos, 0)];
        
        // Remember the item that was placed in the NSUndoManager.
        // If this item is pasted we need to perform a special full line paste.
        rememberCopiedPasteboardItem();
        
        performingHookedCommand = NO;
    } else if (self.selectedRange.length > 0) {
        originalCopyMethod(self_, selector, sender);
        fullLinePasteboardItem = nil;
    }
}

static DVTSourceTextViewEditMethodPtr originalPasteMethod = NULL;
static void pasteHook(id self_, SEL selector, id sender) {
    NSTextView * self = (NSTextView *)self_;
    
    if (isPasteboardItemFullLine() && !performingHookedCommand) {
        performingHookedCommand = YES;
        
        const NSUInteger cursorColumn = [self xcl_cursorColumn];
        
        // We need a slightly differend behaviour when the cursor is on the first line.
        const BOOL cursorIsInFirstLine = [[self string] lineRangeForRange:[self selectedRange]].location == 0;
        
        [self.undoManager beginUndoGrouping];
        
        [self xcl_markCursorPositionForUndo];
        
        if (cursorIsInFirstLine) {
            [self doCommandBySelector:@selector(moveToBeginningOfLine:)];
        } else {
            [self doCommandBySelector:@selector(moveUp:)];
            [self doCommandBySelector:@selector(moveToEndOfLine:)];
            [self doCommandBySelector:@selector(insertNewline:)];
        }
        
        [self doCommandBySelector:@selector(paste:)];
        
        if (!cursorIsInFirstLine) {
            [self doCommandBySelector:@selector(deleteBackward:)];
            [self doCommandBySelector:@selector(moveRight:)];
        }
        
        // Place the cursor on the same column as before on the line below the pasted one.
        [self xcl_setCursorColumn:cursorColumn];
        
        [self.undoManager endUndoGrouping];
        
        performingHookedCommand = NO;
    } else {
        originalPasteMethod(self_, selector, sender);
    }
}

// -----------------------------------------------------------------------------
// NSMenuItem hooks
// -----------------------------------------------------------------------------

typedef void (*NSMenuItemSetEnabledMethodPtr)(id, SEL, BOOL);

static NSMenuItemSetEnabledMethodPtr originalSetEnabledMethod = NULL;
static void setEnabledHook(id self_, SEL selector, BOOL flag) {
    // Don't allow the Cut and Copy menu items to be disabled if there is a text
    // view active. These are normally disabled when there is no selection.
    // Now cut and copy are valid operations even without a selection.
    if (flag == NO && activeTextView != nil && (self_ == cutMenuItem || self_ == copyMenuItem))
        return;
    else
        originalSetEnabledMethod(self_, selector, flag);
}

// -----------------------------------------------------------------------------
// Xcode_copy_line
// -----------------------------------------------------------------------------

static struct {
    const char * className;
    const char * selectorName;
    IMP replacementMethod;
    IMP * originalMethod;
} methodHooks[] = {
    { "DVTSourceTextView", "becomeFirstResponder", (IMP)becomeFirstResponderHook, (IMP *)&originalBecomeFirstResponderMethod },
    { "DVTSourceTextView", "resignFirstResponder", (IMP)resignFirstResponderHook, (IMP *)&originalResignFirstResponderMethod },
    { "DVTSourceTextView", "cut:", (IMP)cutHook, (IMP *)&originalCutMethod },
    { "DVTSourceTextView", "copy:", (IMP)copyHook, (IMP *)&originalCopyMethod },
    { "DVTSourceTextView", "paste:", (IMP)pasteHook, (IMP *)&originalPasteMethod },
    { "NSMenuItem", "setEnabled:", (IMP)setEnabledHook, (IMP *)&originalSetEnabledMethod },
};

const int kHookCount = sizeof(methodHooks) / sizeof(methodHooks[0]);

@interface Xcode_copy_line : NSObject
@end

@implementation Xcode_copy_line

- (id)init {
    // Hook into this notification in order to check menu items, since Xcode plugins get loaded in
    //   applicationWillFinishLaunching as of 6.4.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidFinishLaunching:)
                                                 name:NSApplicationDidFinishLaunchingNotification
                                               object:nil];
    
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    const BOOL hookingSuccessful = (self = [super init]) && [self hookMethods];
    if (!hookingSuccessful)
        [self unhookMethods];
    
    NSLog(@"%@ %@", [self className], hookingSuccessful ? @"initialized" : @"failed to initialize");
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSApplicationDidFinishLaunchingNotification
                                                  object:nil];
}

- (BOOL)hookMethods {
    NSMenuItem * editMenu = [[NSApp mainMenu] itemWithTitle:@"Edit"];
    if (editMenu != nil && [editMenu submenu] != nil) {
        cutMenuItem = [[editMenu submenu] itemWithTitle:@"Cut"];
        copyMenuItem = [[editMenu submenu] itemWithTitle:@"Copy"];
    }

    if (!cutMenuItem) {
        NSLog(@"%@ ERROR: Unable to find Cut menu item", [self className]);
        return NO;
    }
    
    if (!copyMenuItem) {
        NSLog(@"%@ ERROR: Unable to find Copy menu item", [self className]);
        return NO;
    }
    
    for (int i = 0; i < kHookCount; ++i) {
        Class cls = NSClassFromString([NSString stringWithCString:methodHooks[i].className encoding:NSASCIIStringEncoding]);
        if (!cls) {
            NSLog(@"%@ ERROR: Unable to find class %s", [self className], methodHooks[i].className);
            return NO;
        }
        
        SEL selector = NSSelectorFromString([NSString stringWithCString:methodHooks[i].selectorName
                                                               encoding:NSASCIIStringEncoding]);
        Method method = class_getInstanceMethod(cls, selector);
        if (!method) {
            NSLog(@"%@ ERROR: Unable to find method %s of class %s",
                  [self className],
                  methodHooks[i].selectorName,
                  methodHooks[i].className);
            return NO;
        }
        
        *methodHooks[i].originalMethod = (IMP)method_setImplementation(method, methodHooks[i].replacementMethod);
    }
    
    return YES;
}

- (void)unhookMethods {
    for (int i = 0; i < kHookCount; ++i) {
        if (*methodHooks[i].originalMethod == NULL)
            continue;
        
        Class cls = NSClassFromString([NSString stringWithCString:methodHooks[i].className encoding:NSASCIIStringEncoding]);
        if (!cls)
            continue;
        
        SEL selector = NSSelectorFromString([NSString stringWithCString:methodHooks[i].selectorName
                                                               encoding:NSASCIIStringEncoding]);
        Method method = class_getInstanceMethod(cls, selector);
        if (!method)
            continue;
        
        method_setImplementation(method, *methodHooks[i].originalMethod);
    }
}

- (void)dealloc {
    [self unhookMethods];
    [super dealloc];
}

+ (void)pluginDidLoad:(NSBundle *)plugin {
    static dispatch_once_t onceToken;
    static Xcode_copy_line * instance;
    NSString *currentApplicationName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
    
    if ([currentApplicationName isEqual:@"Xcode"])
        dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
}

@end

// -----------------------------------------------------------------------------
