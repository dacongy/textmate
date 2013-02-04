extern NSString* const FFSearchInDocument;
extern NSString* const FFSearchInSelection;
extern NSString* const FFSearchInOpenFiles;
extern NSString* const FFSearchInFolder;

@interface FindWindowController : NSWindowController
@property (nonatomic, retain, readonly) NSOutlineView* resultsOutlineView;
@property (nonatomic) BOOL showsResultsOutlineView;
@property (nonatomic) BOOL showResultsCollapsed;

@property (nonatomic, retain) NSString* projectFolder;
@property (nonatomic, retain) NSString* searchFolder;
@property (nonatomic, retain) NSString* searchIn;

@property (nonatomic, retain) NSString* findString;
@property (nonatomic, retain) NSString* replaceString;
@property (nonatomic, readonly) NSString* globString;

@property (nonatomic) BOOL ignoreCase;
@property (nonatomic) BOOL ignoreWhitespace;
@property (nonatomic) BOOL regularExpression;
@property (nonatomic) BOOL wrapAround;

@property (nonatomic, getter = isBusy) BOOL busy;
@property (nonatomic, retain) NSString* statusString;

- (void)showPopoverWithString:(NSString*)aString;

// not implemented
@property (nonatomic) BOOL followLinks;
@property (nonatomic) BOOL fullWords;
@property (nonatomic) BOOL searchHiddenFolders;
@end
