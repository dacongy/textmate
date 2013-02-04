#import "FindWindowController.h"
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakPasteboard.h>
#import <OakAppKit/OakPasteboardSelector.h>
#import <OakFoundation/OakHistoryList.h>
#import <OakFoundation/OakFoundation.h>
#import <Preferences/Keys.h>

// TODO Update [search] ‘in’ pop-up menu
// TODO Make Next/Previous buttons work (for Find All)
// TODO Show replacement previews
// TODO Update ‘showResultsCollapsed’ property when starting new search
// TODO Update menu title for “Collapse/Expand Results”
// TODO Mouse tracking for proxy icon
// TODO Hide/update regexp error pop-over window when editing regexp
// TODO Use libdispatch for searcher
// TODO Syntax highlight matches
// TODO Property for “open documents”
// TODO Ability to “search selection”
// TODO Let Find window follow [⇧]⌘G in document (for Find All)
// TODO Close buttons on file headings to remove results
// TODO Let file headings stick to top of table view (until displaced by the next file header)
// TODO Let Find window partake in session restore
// TODO Remove Full Words menu item from Edit → Find menu
// TODO Save/restore height of results outline view
// TODO Find options (like regular expression) is not reset when using ⌘E

NSString* const FFSearchInDocument   = @"FFSearchInDocument";
NSString* const FFSearchInSelection  = @"FFSearchInSelection";
NSString* const FFSearchInOpenFiles  = @"FFSearchInOpenFiles";
NSString* const FFSearchInFolder     = @"FFSearchInFolder";

@interface OakAutoSizingTextField : NSTextField
@property (nonatomic) NSSize myIntrinsicContentSize;
@end

@implementation OakAutoSizingTextField
- (NSSize)intrinsicContentSize
{
	if(NSEqualSizes(self.myIntrinsicContentSize, NSZeroSize))
		return [super intrinsicContentSize];
	return self.myIntrinsicContentSize;
}
@end

static NSTextField* OakCreateLabel (NSString* label)
{
	NSTextField* res = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
	res.font            = [NSFont controlContentFontOfSize:[NSFont labelFontSize]];
	res.stringValue     = label;
	res.bordered        = NO;
	res.editable        = NO;
	res.selectable      = NO;
	res.bezeled         = NO;
	res.drawsBackground = NO;
	return res;
}

static OakAutoSizingTextField* OakCreateTextField (id <NSTextFieldDelegate> delegate)
{
	OakAutoSizingTextField* res = [[[OakAutoSizingTextField alloc] initWithFrame:NSZeroRect] autorelease];
	res.font = [NSFont controlContentFontOfSize:0];
	[[res cell] setWraps:YES];
	res.delegate = delegate;
	return res;
}

static NSButton* OakCreateHistoryButton ()
{
	NSButton* res = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
	res.bezelStyle = NSRoundedDisclosureBezelStyle;
	res.buttonType = NSMomentaryLightButton;
	res.title      = @"";
	return res;
}

static NSButton* OakCreateCheckBox (NSString* label)
{
	NSButton* res = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
	[res setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationVertical];
	res.buttonType = NSSwitchButton;
	res.font       = [NSFont controlContentFontOfSize:0];
	res.title      = label;
	return res;
}

static NSPopUpButton* OakCreatePopUpButton (BOOL pullsDown = NO)
{
	NSPopUpButton* res = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO] autorelease];
	res.font = [NSFont controlContentFontOfSize:0];
	res.pullsDown = pullsDown;
	return res;
}

static NSComboBox* OakCreateComboBox ()
{
	NSComboBox* res = [[[NSComboBox alloc] initWithFrame:NSZeroRect] autorelease];
	res.font = [NSFont controlContentFontOfSize:0];
	return res;
}

static NSOutlineView* OakCreateOutlineView (NSScrollView** scrollViewOut)
{
	NSOutlineView* res = [[[NSOutlineView alloc] initWithFrame:NSZeroRect] autorelease];
	res.focusRingType                      = NSFocusRingTypeNone;
	res.allowsMultipleSelection            = YES;
	res.autoresizesOutlineColumn           = NO;
	res.usesAlternatingRowBackgroundColors = YES;
	res.headerView                         = nil;

	NSTableColumn* tableColumn = [[[NSTableColumn alloc] initWithIdentifier:@"checkbox"] autorelease];
	NSButtonCell* dataCell = [[[NSButtonCell alloc] init] autorelease];
	dataCell.buttonType    = NSSwitchButton;
	dataCell.controlSize   = NSSmallControlSize;
	dataCell.imagePosition = NSImageOnly;
	dataCell.font          = [NSFont controlContentFontOfSize:[NSFont smallSystemFontSize]];
	tableColumn.dataCell = dataCell;
	tableColumn.width    = 50;
	[res addTableColumn:tableColumn];

	tableColumn = [[[NSTableColumn alloc] initWithIdentifier:@"match"] autorelease];
	[tableColumn setEditable:NO];
	NSTextFieldCell* cell = tableColumn.dataCell;
	cell.font = [NSFont controlContentFontOfSize:[NSFont smallSystemFontSize]];
	[res addTableColumn:tableColumn];

	res.rowHeight = 14;

	NSScrollView* scrollView = [[[NSScrollView alloc] initWithFrame:NSZeroRect] autorelease];
	scrollView.hasVerticalScroller   = YES;
	scrollView.hasHorizontalScroller = NO;
	scrollView.borderType            = NSNoBorder;
	scrollView.documentView          = res;

	if(scrollViewOut)
		*scrollViewOut = scrollView;

	return res;
}

static NSProgressIndicator* OakCreateProgressIndicator ()
{
	NSProgressIndicator* res = [[[NSProgressIndicator alloc] initWithFrame:NSZeroRect] autorelease];
	res.style                = NSProgressIndicatorSpinningStyle;
	res.controlSize          = NSSmallControlSize;
	res.displayedWhenStopped = NO;
	return res;
}

static NSButton* OakCreateButton (NSString* label, NSBezelStyle bezel = NSRoundedBezelStyle)
{
	NSButton* res = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
	res.buttonType = NSMomentaryPushInButton;
	res.bezelStyle = bezel;
	res.title      = label;
	res.font       = [NSFont controlContentFontOfSize:13];
	return res;
}

@interface FindWindowController () <NSTextFieldDelegate, NSWindowDelegate, NSMenuDelegate>
{
	BOOL _wrapAround;
	BOOL _ignoreCase;
}
@property (nonatomic, retain) NSTextField*              findLabel;
@property (nonatomic, retain) OakAutoSizingTextField*   findTextField;
@property (nonatomic, retain) NSButton*                 findHistoryButton;

@property (nonatomic, retain) NSButton*                 countButton;

@property (nonatomic, retain) NSTextField*              replaceLabel;
@property (nonatomic, retain) OakAutoSizingTextField*   replaceTextField;
@property (nonatomic, retain) NSButton*                 replaceHistoryButton;

@property (nonatomic, retain) NSTextField*              optionsLabel;
@property (nonatomic, retain) NSButton*                 ignoreCaseCheckBox;
@property (nonatomic, retain) NSButton*                 ignoreWhitespaceCheckBox;
@property (nonatomic, retain) NSButton*                 regularExpressionCheckBox;
@property (nonatomic, retain) NSButton*                 wrapAroundCheckBox;

@property (nonatomic, retain) NSTextField*              whereLabel;
@property (nonatomic, retain) NSPopUpButton*            wherePopUpButton;
@property (nonatomic, retain) NSTextField*              matchingLabel;
@property (nonatomic, retain) NSComboBox*               globTextField;
@property (nonatomic, retain) NSPopUpButton*            actionsPopUpButton;

@property (nonatomic, retain) NSView*                   resultsTopDivider;
@property (nonatomic, retain) NSScrollView*             resultsScrollView;
@property (nonatomic, retain, readwrite) NSOutlineView* resultsOutlineView;
@property (nonatomic, retain) NSView*                   resultsBottomDivider;

@property (nonatomic, retain) NSProgressIndicator*      progressIndicator;
@property (nonatomic, retain) NSTextField*              statusTextField;

@property (nonatomic, retain) NSButton*                 findAllButton;
@property (nonatomic, retain) NSButton*                 replaceAllButton;
@property (nonatomic, retain) NSButton*                 replaceAndFindButton;
@property (nonatomic, retain) NSButton*                 findPreviousButton;
@property (nonatomic, retain) NSButton*                 findNextButton;

@property (nonatomic, retain) NSObjectController*       objectController;
@property (nonatomic, retain) OakHistoryList*           globHistoryList;
@property (nonatomic, retain) NSMutableArray*           myConstraints;

@property (nonatomic, assign)   BOOL                    folderSearch;
@property (nonatomic, readonly) BOOL                    canIgnoreWhitespace;
@end

@implementation FindWindowController
+ (NSSet*)keyPathsForValuesAffectingCanIgnoreWhitespace { return [NSSet setWithObject:@"regularExpression"]; }
+ (NSSet*)keyPathsForValuesAffectingIgnoreWhitespace    { return [NSSet setWithObject:@"regularExpression"]; }

- (id)init
{
	NSRect r = [[NSScreen mainScreen] visibleFrame];
	if((self = [super initWithWindow:[[NSPanel alloc] initWithContentRect:NSMakeRect(NSMidX(r)-100, NSMidY(r)+100, 200, 200) styleMask:(NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask|NSMiniaturizableWindowMask) backing:NSBackingStoreBuffered defer:NO]]))
	{
		self.window.title             = @"Find";
		self.window.frameAutosaveName = @"Find";
		self.window.hidesOnDeactivate = NO;
		self.window.delegate          = self;

		self.findLabel                 = OakCreateLabel(@"Find:");
		self.findTextField             = OakCreateTextField(self);
		self.findHistoryButton         = OakCreateHistoryButton();
		self.countButton               = OakCreateButton(@"Σ", NSSmallSquareBezelStyle);

		self.replaceLabel              = OakCreateLabel(@"Replace:");
		self.replaceTextField          = OakCreateTextField(self);
		self.replaceHistoryButton      = OakCreateHistoryButton();

		self.optionsLabel              = OakCreateLabel(@"Options:");

		self.ignoreCaseCheckBox        = OakCreateCheckBox(@"Ignore Case");
		self.ignoreWhitespaceCheckBox  = OakCreateCheckBox(@"Ignore Whitespace");
		self.regularExpressionCheckBox = OakCreateCheckBox(@"Regular Expression");
		self.wrapAroundCheckBox        = OakCreateCheckBox(@"Wrap Around");

		self.whereLabel                = OakCreateLabel(@"In:");
		self.wherePopUpButton          = OakCreatePopUpButton();
		self.matchingLabel             = OakCreateLabel(@"matching");
		self.globTextField             = OakCreateComboBox();
		self.actionsPopUpButton        = OakCreatePopUpButton(YES /* pulls down */);

		NSScrollView* resultsScrollView = nil;
		self.resultsTopDivider         = OakCreateHorizontalLine([NSColor colorWithCalibratedWhite:0.500 alpha:1]);
		self.resultsOutlineView        = OakCreateOutlineView(&resultsScrollView);
		self.resultsScrollView         = resultsScrollView;
		self.resultsBottomDivider      = OakCreateHorizontalLine([NSColor colorWithCalibratedWhite:0.500 alpha:1]);

		self.progressIndicator         = OakCreateProgressIndicator();
		self.statusTextField           = OakCreateLabel(@"Found 1,234 results.");
		self.statusTextField.font      = [NSFont controlContentFontOfSize:[NSFont smallSystemFontSize]];

		self.findAllButton             = OakCreateButton(@"Find All");
		self.replaceAllButton          = OakCreateButton(@"Replace All");
		self.replaceAndFindButton      = OakCreateButton(@"Replace & Find");
		self.findPreviousButton        = OakCreateButton(@"Previous");
		self.findNextButton            = OakCreateButton(@"Next");

		// ==============================
		// = Create “where” pop-up menu =
		// ==============================

		NSMenu* whereMenu = self.wherePopUpButton.menu;
		[whereMenu removeAllItems];
		[whereMenu addItemWithTitle:@"Document" action:@selector(takeSearchFolderFrom:) keyEquivalent:@""];
		[whereMenu addItemWithTitle:@"Selection" action:@selector(takeSearchFolderFrom:) keyEquivalent:@""];
		[whereMenu addItem:[NSMenuItem separatorItem]];
		[whereMenu addItemWithTitle:@"Open Files" action:@selector(takeSearchFolderFrom:) keyEquivalent:@""];
		[whereMenu addItemWithTitle:@"Project Folder" action:@selector(takeSearchFolderFrom:) keyEquivalent:@""];
		[whereMenu addItemWithTitle:@"Other Folder…" action:@selector(takeSearchFolderFrom:) keyEquivalent:@""];
		[whereMenu addItem:[NSMenuItem separatorItem]];
		[whereMenu addItemWithTitle:@"~" action:@selector(takeSearchFolderFrom:) keyEquivalent:@""];

		NSInteger tag = 0;
		for(NSMenuItem* item : [whereMenu itemArray])
			item.tag = item.isSeparatorItem ? 0 : ++tag;

		// =============================
		// = Create action pop-up menu =
		// =============================

		NSMenu* actionMenu = self.actionsPopUpButton.menu;
		[actionMenu removeAllItems];

		NSMenuItem* titleItem = [actionMenu addItemWithTitle:@"" action:@selector(nop:) keyEquivalent:@""];
		titleItem.image = [NSImage imageNamed:NSImageNameActionTemplate];

		[actionMenu addItemWithTitle:@"Follow Symbolic Links" action:@selector(nop:) keyEquivalent:@""];
		[actionMenu addItemWithTitle:@"Search Hidden Folders" action:@selector(nop:) keyEquivalent:@""];
		[actionMenu addItem:[NSMenuItem separatorItem]];
		[[actionMenu addItemWithTitle:@"Collapse/Expand Results" action:@selector(takeLevelToFoldFrom:) keyEquivalent:@"1"] setKeyEquivalentModifierMask:(NSAlternateKeyMask|NSCommandKeyMask)];

		NSMenuItem* selectResultItem = [actionMenu addItemWithTitle:@"Select Result" action:NULL keyEquivalent:@""];
		selectResultItem.submenu = [[NSMenu new] autorelease];
		selectResultItem.submenu.delegate = self;

		[actionMenu addItem:[NSMenuItem separatorItem]];
		[actionMenu addItemWithTitle:@"Copy Matching Parts"                action:@selector(copyMatchingParts:)             keyEquivalent:@""];
		[actionMenu addItemWithTitle:@"Copy Matching Parts With Filenames" action:@selector(copyMatchingPartsWithFilename:) keyEquivalent:@""];
		[actionMenu addItemWithTitle:@"Copy Entire Lines"                  action:@selector(copyEntireLines:)               keyEquivalent:@""];
		[actionMenu addItemWithTitle:@"Copy Entire Lines With Filenames"   action:@selector(copyEntireLinesWithFilename:)   keyEquivalent:@""];

		// =============================

		self.findHistoryButton.action    = @selector(showFindHistory:);
		self.replaceHistoryButton.action = @selector(showReplaceHistory:);
		self.countButton.action          = @selector(countOccurrences:);
		self.findAllButton.action        = @selector(findAll:);
		self.replaceAllButton.action     = @selector(replaceAll:);
		self.replaceAndFindButton.action = @selector(replaceAndFind:);
		self.findPreviousButton.action   = @selector(findPrevious:);
		self.findNextButton.action       = @selector(findNext:);

		self.objectController = [[[NSObjectController alloc] initWithContent:self] autorelease];
		self.globHistoryList  = [[[OakHistoryList alloc] initWithName:@"Find in Folder Globs.default" stackSize:10 defaultItems:@"*", @"*.txt", @"*.{c,h}", nil] autorelease];

		[self.findTextField             bind:@"value"         toObject:_objectController withKeyPath:@"content.findString"           options:nil];
		[self.replaceTextField          bind:@"value"         toObject:_objectController withKeyPath:@"content.replaceString"        options:nil];
		[self.globTextField             bind:@"value"         toObject:_objectController withKeyPath:@"content.globHistoryList.head" options:nil];
		[self.globTextField             bind:@"contentValues" toObject:_objectController withKeyPath:@"content.globHistoryList.list" options:nil];
		[self.globTextField             bind:@"enabled"       toObject:_objectController withKeyPath:@"content.folderSearch"         options:nil];
		[self.actionsPopUpButton        bind:@"enabled"       toObject:_objectController withKeyPath:@"content.folderSearch"         options:nil];
		[self.ignoreCaseCheckBox        bind:@"value"         toObject:_objectController withKeyPath:@"content.ignoreCase"           options:nil];
		[self.ignoreWhitespaceCheckBox  bind:@"value"         toObject:_objectController withKeyPath:@"content.ignoreWhitespace"     options:nil];
		[self.regularExpressionCheckBox bind:@"value"         toObject:_objectController withKeyPath:@"content.regularExpression"    options:nil];
		[self.wrapAroundCheckBox        bind:@"value"         toObject:_objectController withKeyPath:@"content.wrapAround"           options:nil];
		[self.ignoreWhitespaceCheckBox  bind:@"enabled"       toObject:_objectController withKeyPath:@"content.canIgnoreWhitespace"  options:nil];
		[self.statusTextField           bind:@"value"         toObject:_objectController withKeyPath:@"content.statusString"         options:nil];

		NSView* contentView = self.window.contentView;
		for(NSView* view in [self.allViews allValues])
		{
			[view setTranslatesAutoresizingMaskIntoConstraints:NO];
			[contentView addSubview:view];
		}

		for(NSView* view in @[ self.resultsTopDivider, self.resultsScrollView, self.resultsBottomDivider, self.progressIndicator ])
			[view setTranslatesAutoresizingMaskIntoConstraints:NO];

		[self updateConstraints];

		self.searchIn = FFSearchInDocument;

		// setup find/replace strings/options
		[self userDefaultsDidChange:nil];
		[self findClipboardDidChange:nil];
		[self replaceClipboardDidChange:nil];

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDefaultsDidChange:) name:NSUserDefaultsDidChangeNotification object:[NSUserDefaults standardUserDefaults]];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(findClipboardDidChange:) name:OakPasteboardDidChangeNotification object:[OakPasteboard pasteboardWithName:NSFindPboard]];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(replaceClipboardDidChange:) name:OakPasteboardDidChangeNotification object:[OakPasteboard pasteboardWithName:NSReplacePboard]];
	}
	return self;
}

- (BOOL)menuHasKeyEquivalent:(NSMenu*)aMenu forEvent:(NSEvent*)anEvent target:(id*)anId action:(SEL*)aSEL
{
	return NO;
}

- (void)menuNeedsUpdate:(NSMenu*)aMenu
{
	[aMenu removeAllItems];
	[NSApp sendAction:@selector(updateGoToMenu:) to:nil from:aMenu];
}

- (NSDictionary*)allViews
{
	NSDictionary* views = @{
		@"findLabel"         : self.findLabel,
		@"find"              : self.findTextField,
		@"findHistory"       : self.findHistoryButton,
		@"count"             : self.countButton,
		@"replaceLabel"      : self.replaceLabel,
		@"replace"           : self.replaceTextField,
		@"replaceHistory"    : self.replaceHistoryButton,

		@"optionsLabel"      : self.optionsLabel,
		@"regularExpression" : self.regularExpressionCheckBox,
		@"ignoreWhitespace"  : self.ignoreWhitespaceCheckBox,
		@"ignoreCase"        : self.ignoreCaseCheckBox,
		@"wrapAround"        : self.wrapAroundCheckBox,

		@"whereLabel"        : self.whereLabel,
		@"where"             : self.wherePopUpButton,
		@"matching"          : self.matchingLabel,
		@"glob"              : self.globTextField,
		@"actions"           : self.actionsPopUpButton,

		@"status"            : self.statusTextField,

		@"findAll"           : self.findAllButton,
		@"replaceAll"        : self.replaceAllButton,
		@"replaceAndFind"    : self.replaceAndFindButton,
		@"previous"          : self.findPreviousButton,
		@"next"              : self.findNextButton,
	};

	if(self.showsResultsOutlineView)
	{
		NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithDictionary:views];
		[dict addEntriesFromDictionary:@{
			@"resultsTopDivider"    : self.resultsTopDivider,
			@"results"              : self.resultsScrollView,
			@"resultsBottomDivider" : self.resultsBottomDivider,
		}];
		views = dict;
	}

	if(self.isBusy)
	{
		NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithDictionary:views];
		[dict addEntriesFromDictionary:@{
			@"busy" : self.progressIndicator,
		}];
		views = dict;
	}

	return views;
}

#ifndef CONSTRAINT
#define CONSTRAINT(str, align) [_myConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:str options:align metrics:nil views:views]]
#endif

- (void)updateConstraints
{
	if(_myConstraints)
		[self.window.contentView removeConstraints:_myConstraints];
	self.myConstraints = [NSMutableArray array];

	NSDictionary* views = self.allViews;

	CONSTRAINT(@"H:|-(>=10)-[findLabel]-[find(>=100)]",                0);
	CONSTRAINT(@"H:[find]-(5)-[findHistory]-[count(==findHistory)]-|", NSLayoutFormatAlignAllTop);
	CONSTRAINT(@"V:[count(==21)]",                                     NSLayoutFormatAlignAllLeft|NSLayoutFormatAlignAllRight);
	CONSTRAINT(@"H:|-(>=10)-[replaceLabel]-[replace]",        0);
	CONSTRAINT(@"H:[replace]-(5)-[replaceHistory]",                    NSLayoutFormatAlignAllTop);
	CONSTRAINT(@"V:|-[find]-[replace]",                                NSLayoutFormatAlignAllLeft|NSLayoutFormatAlignAllRight);

	[_myConstraints addObject:[NSLayoutConstraint constraintWithItem:self.findLabel attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.findTextField attribute:NSLayoutAttributeTop multiplier:1 constant:6]];
	[_myConstraints addObject:[NSLayoutConstraint constraintWithItem:self.replaceLabel attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.replaceTextField attribute:NSLayoutAttributeTop multiplier:1 constant:6]];

	CONSTRAINT(@"H:|-(==20@100)-[optionsLabel]-[regularExpression]-[ignoreWhitespace]-(>=20)-|", NSLayoutFormatAlignAllBaseline);
	CONSTRAINT(@"H:[ignoreCase(==regularExpression)]-[wrapAround(==ignoreWhitespace)]",      NSLayoutFormatAlignAllTop|NSLayoutFormatAlignAllBottom);
	CONSTRAINT(@"V:[replace]-[regularExpression]-[ignoreCase]",                              NSLayoutFormatAlignAllLeft);
	CONSTRAINT(@"V:[replace]-[ignoreWhitespace]-[wrapAround]",                               0);

	CONSTRAINT(@"H:|-(>=10)-[whereLabel]-[where]-[matching]", NSLayoutFormatAlignAllBaseline);
	CONSTRAINT(@"H:[matching]-[glob]",                        0);
	CONSTRAINT(@"H:[where]-(>=8)-[glob]-[actions]",           NSLayoutFormatAlignAllTop);
	CONSTRAINT(@"V:[ignoreCase]-[where]",                     NSLayoutFormatAlignAllLeft);
	[_myConstraints addObject:[NSLayoutConstraint constraintWithItem:self.replaceTextField attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self.globTextField attribute:NSLayoutAttributeRight multiplier:1 constant:0]];

	if(self.showsResultsOutlineView)
	{
		CONSTRAINT(@"H:|[results(==resultsTopDivider,==resultsBottomDivider)]|", 0);
		CONSTRAINT(@"V:[where]-[resultsTopDivider][results(>=200)][resultsBottomDivider]-[status]", 0);
	}
	else
	{
		CONSTRAINT(@"V:[where]-[status]", 0);
	}

	if(self.isBusy)
	{
		CONSTRAINT(@"H:|-[busy]-[status]-|", NSLayoutFormatAlignAllCenterY);
	}
	else
	{
		CONSTRAINT(@"H:|-[status]-|", 0);
	}

	CONSTRAINT(@"H:|-[findAll]-[replaceAll]-(>=8)-[replaceAndFind]-[previous]-[next]-|", NSLayoutFormatAlignAllBottom);
	CONSTRAINT(@"V:[status]-[findAll]-|", 0);

	[self.window.contentView addConstraints:_myConstraints];

	self.window.initialFirstResponder = self.findTextField;
	if(self.showsResultsOutlineView)
	{
		NSView* keyViewLoop[] = { self.findTextField, self.replaceTextField, self.globTextField, self.countButton, self.regularExpressionCheckBox, self.ignoreWhitespaceCheckBox, self.ignoreCaseCheckBox, self.wrapAroundCheckBox, self.wherePopUpButton, self.resultsOutlineView, self.findAllButton, self.replaceAllButton, self.replaceAndFindButton, self.findPreviousButton, self.findNextButton };
		for(size_t i = 0; i < sizeofA(keyViewLoop); ++i)
			keyViewLoop[i].nextKeyView = keyViewLoop[(i + 1) % sizeofA(keyViewLoop)];
	}
	else
	{
		NSView* keyViewLoop[] = { self.findTextField, self.replaceTextField, self.globTextField, self.countButton, self.regularExpressionCheckBox, self.ignoreWhitespaceCheckBox, self.ignoreCaseCheckBox, self.wrapAroundCheckBox, self.wherePopUpButton, self.findAllButton, self.replaceAllButton, self.replaceAndFindButton, self.findPreviousButton, self.findNextButton };
		for(size_t i = 0; i < sizeofA(keyViewLoop); ++i)
			keyViewLoop[i].nextKeyView = keyViewLoop[(i + 1) % sizeofA(keyViewLoop)];
	}
}

- (void)userDefaultsDidChange:(NSNotification*)aNotification
{
	self.ignoreCase = [[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsFindIgnoreCase];
	self.wrapAround = [[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsFindWrapAround];
}

- (void)findClipboardDidChange:(NSNotification*)aNotification
{
	OakPasteboardEntry* entry = [[OakPasteboard pasteboardWithName:NSFindPboard] current];
	self.findString        = entry.string ?: @"";
	self.fullWords         = entry.fullWordMatch;
	self.ignoreWhitespace  = entry.ignoreWhitespace;
	self.regularExpression = entry.regularExpression;
}

- (void)replaceClipboardDidChange:(NSNotification*)aNotification
{
	self.replaceString = [[[OakPasteboard pasteboardWithName:NSReplacePboard] current] string] ?: @"";
}

- (void)showWindow:(id)sender
{
	BOOL isVisible = [self isWindowLoaded] && [self.window isVisible];
	[super showWindow:sender];
	if(!isVisible)
		[self.window makeFirstResponder:self.findTextField];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (BOOL)commitEditing
{
	id currentResponder = [[self window] firstResponder];
	id view = [currentResponder isKindOfClass:[NSTextView class]] ? [currentResponder delegate] : currentResponder;
	BOOL res = [self.objectController commitEditing];
	if([[self window] firstResponder] != currentResponder && view)
		[[self window] makeFirstResponder:view];

	// =====================
	// = Update Pasteboard =
	// =====================

	NSDictionary* newOptions = @{
		OakFindRegularExpressionOption : @(self.regularExpression),
		OakFindIgnoreWhitespaceOption  : @(self.ignoreWhitespace),
		OakFindFullWordsOption         : @(self.fullWords),
	};

	if(NSNotEmptyString(_findString))
	{
		OakPasteboardEntry* oldEntry = [[OakPasteboard pasteboardWithName:NSFindPboard] current];
		if(!oldEntry || ![oldEntry.string isEqualToString:_findString])
			[[OakPasteboard pasteboardWithName:NSFindPboard] addEntry:[OakPasteboardEntry pasteboardEntryWithString:_findString andOptions:newOptions]];
		else if(![oldEntry.options isEqualToDictionary:newOptions])
			oldEntry.options = newOptions;
	}

	if(_replaceString)
	{
		NSString* oldReplacement = [[[OakPasteboard pasteboardWithName:NSReplacePboard] current] string];
		if(!oldReplacement || ![oldReplacement isEqualToString:_replaceString])
			[[OakPasteboard pasteboardWithName:NSReplacePboard] addEntry:[OakPasteboardEntry pasteboardEntryWithString:_replaceString]];
	}

	return res;
}

- (void)windowDidResignKey:(NSNotification*)aNotification
{
	[self commitEditing];
}

- (void)windowWillClose:(NSNotification*)aNotification
{
	[self commitEditing];
}

- (void)takeSearchFolderFrom:(NSMenuItem*)menuItem
{
	switch([menuItem tag])
	{
		case 1: self.searchIn = FFSearchInDocument;  break;
		case 2: self.searchIn = FFSearchInSelection; break;
		case 3: self.searchIn = FFSearchInOpenFiles; break;
		case 4: self.searchIn = FFSearchInFolder;    break;
		case 5: self.searchIn = FFSearchInFolder;    break;
	}
	self.searchFolder = [menuItem representedObject];
}

- (IBAction)showFindHistory:(id)sender
{
	if(![[[OakPasteboardSelector sharedInstance] window] isVisible])
		[[OakPasteboard pasteboardWithName:NSFindPboard] selectItemForControl:self.findTextField];
	// if the panel is visible it will automatically be hidden due to the mouse click
}

- (IBAction)showReplaceHistory:(id)sender
{
	if(![[[OakPasteboardSelector sharedInstance] window] isVisible])
		[[OakPasteboard pasteboardWithName:NSReplacePboard] selectItemForControl:self.replaceTextField];
	// if the panel is visible it will automatically be hidden due to the mouse click
}

- (void)showPopoverWithString:(NSString*)aString
{
	NSViewController* viewController = [[[NSViewController alloc] init] autorelease];
	NSTextField* textField = OakCreateLabel(aString);
	[textField sizeToFit];
	viewController.view = textField;

	NSPopover* popover = [[[NSPopover alloc] init] autorelease];
	popover.behavior = NSPopoverBehaviorTransient;
	popover.contentViewController = viewController;
	[popover showRelativeToRect:NSZeroRect ofView:self.findTextField preferredEdge:NSMaxYEdge];

	[self.window makeFirstResponder:self.findTextField];
}

- (void)setShowsResultsOutlineView:(BOOL)flag
{
	if(_showsResultsOutlineView == flag)
		return;

	for(NSView* view in @[ self.resultsTopDivider, self.resultsScrollView, self.resultsBottomDivider ])
	{
		if(_showsResultsOutlineView = flag)
				[self.window.contentView addSubview:view];
		else	[view removeFromSuperview];
	}
	[self updateConstraints];
}

- (void)setShowResultsCollapsed:(BOOL)flag
{
	if(_showResultsCollapsed = flag)
			[self.resultsOutlineView collapseItem:nil collapseChildren:YES];
	else	[self.resultsOutlineView expandItem:nil expandChildren:YES];
	[self.resultsOutlineView setNeedsDisplay:YES];
}

- (void)setBusy:(BOOL)busyFlag
{
	if(_busy == busyFlag)
		return;

	if(_busy = busyFlag)
	{
		[self.window.contentView addSubview:self.progressIndicator];
		[self.progressIndicator startAnimation:self];
	}
	else
	{
		[self.progressIndicator stopAnimation:self];
		[self.progressIndicator removeFromSuperview];
	}
	[self updateConstraints];
}

- (void)setSearchIn:(NSString*)aString
{
	_searchIn = [aString retain];
	self.folderSearch = ![@[ FFSearchInDocument, FFSearchInSelection ] containsObject:_searchIn];
}

- (void)setFolderSearch:(BOOL)flag
{
	if(_folderSearch == flag)
		return;

	_folderSearch = flag;
	self.findNextButton.keyEquivalent = flag ? @"" : @"\r";
	self.findAllButton.keyEquivalent  = flag ? @"\r" : @"";
	self.showsResultsOutlineView      = flag;
}

- (NSString*)findString    { [self commitEditing]; return _findString; }
- (NSString*)replaceString { [self commitEditing]; return _replaceString; }
- (NSString*)globString    { [self commitEditing]; return _globHistoryList.head; }

- (void)setIgnoreCase:(BOOL)flag       { if(_ignoreCase != flag) [[NSUserDefaults standardUserDefaults] setObject:@(_ignoreCase = flag) forKey:kUserDefaultsFindIgnoreCase]; }
- (void)setWrapAround:(BOOL)flag       { if(_wrapAround != flag) [[NSUserDefaults standardUserDefaults] setObject:@(_wrapAround = flag) forKey:kUserDefaultsFindWrapAround]; }
- (BOOL)ignoreWhitespace               { return _ignoreWhitespace && self.canIgnoreWhitespace; }
- (BOOL)canIgnoreWhitespace            { return _regularExpression == NO; }

- (void)setProjectFolder:(NSString*)aFolder
{
	if(_projectFolder != aFolder && ![_projectFolder isEqualToString:aFolder])
	{
		[_projectFolder release];
		_projectFolder = [(aFolder ?: @"") retain];
		self.globHistoryList = [[[OakHistoryList alloc] initWithName:[NSString stringWithFormat:@"Find in Folder Globs.%@", _projectFolder] stackSize:10 defaultItems:@"*", @"*.txt", @"*.{c,h}", nil] autorelease];
	}
}

- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)command
{
	if(control == self.findTextField && command == @selector(moveDown:))
	{
		[self showFindHistory:control];
		return YES;
	}
	else if(control == self.replaceTextField && command == @selector(moveDown:))
	{
		[self showReplaceHistory:control];
		return YES;
	}
	return NO;
}

- (void)controlTextDidChange:(NSNotification*)aNotification
{
	OakAutoSizingTextField* textField = [aNotification object];
	NSDictionary* userInfo = [aNotification userInfo];
	NSTextView* textView = userInfo[@"NSFieldEditor"];

	if(textView && textField)
	{
		NSTextFieldCell* cell = [[textField.cell copy] autorelease];
		cell.stringValue = textView.string;

		NSRect bounds = [textField bounds];
		bounds.size.height = CGFLOAT_MAX;
		bounds.size = [cell cellSizeForBounds:bounds];

		textField.myIntrinsicContentSize = NSMakeSize(NSViewNoInstrinsicMetric, NSHeight(bounds));
		[textField invalidateIntrinsicContentSize];
	}
}
@end
