/* GlkWindow.m: Window objc class (and subclasses)
	for IosGlk, the iOS implementation of the Glk API.
	Designed by Andrew Plotkin <erkyrath@eblong.com>
	http://eblong.com/zarf/glk/
*/

/*	GlkWindow is the base class representing a Glk window. The subclasses represent the window types (textgrid, textbuffer, etc.)

	(The iOS View classes for these window types are GlkWinGridView, GlkWinBufferView, etc.)
	
	The encapsulation isn't very good in this file, because I kept most of the structure of the C Glk implementations -- specifically GlkTerm. The top-level "glk_" functions remained the same, and can be found in GlkWindowLayer.c. The internal "gli_" functions have become methods on the ObjC GlkWindow class. So both layers wind up futzing with GlkWindow internals.
*/

#import "GlkLibrary.h"
#import "GlkWindow.h"
#import "GlkStream.h"
#import "StyleSet.h"
#import "GlkUtilTypes.h"

@implementation GlkWindow
/* GlkWindow: the base class. */

@synthesize library;
@synthesize tag;
@synthesize type;
@synthesize rock;
@synthesize parent;
@synthesize char_request;
@synthesize line_request;
@synthesize style;
@synthesize stream;
@synthesize echostream;
@synthesize styleset;
@synthesize bbox;

static NSCharacterSet *newlineCharSet; /* retained forever */

+ (void) initialize {
	/* We need this for breaking up printing strings, so we set it up at class init time. I think this shows up as a memory leak in Apple's tools -- sorry about that. */
	newlineCharSet = [[NSCharacterSet characterSetWithCharactersInString:@"\n"] retain];
}

/* Create a window with a given type. (But not Pair windows -- those use a different path.) This is invoked by glk_window_open().
*/
+ (GlkWindow *) windowWithType:(glui32)type rock:(glui32)rock {
	GlkWindow *win;
	switch (type) {
		case wintype_TextBuffer:
			win = [[[GlkWindowBuffer alloc] initWithType:type rock:rock] autorelease];
			win.styleset = [[[StyleSet alloc] init] autorelease];
			[win.styleset setFontFamily:@"Helvetica Neue" size:14.0];
			break;
		case wintype_TextGrid:
			win = [[[GlkWindowGrid alloc] initWithType:type rock:rock] autorelease];
			win.styleset = [[[StyleSet alloc] init] autorelease];
			[win.styleset setFontFamily:@"Courier" size:14.0];
			break;
		case wintype_Pair:
			/* You can't create a pair window this way. */
			[GlkLibrary strictWarning:@"window_open: cannot open pair window directly"];
			win = nil;
			break;
		default:
			/* Unknown window type -- do not print a warning, just return nil to indicate that it's not possible. */
			win = nil;
			break;
	}
	return win;
}

/* GlkWindow designated initializer. */
- (id) initWithType:(glui32)wintype rock:(glui32)winrock {
	self = [super init];
	
	if (self) {
		self.library = [GlkLibrary singleton];
		inlibrary = YES;
		
		self.tag = [library newTag];
		type = wintype;
		rock = winrock;
		
		parent = nil;
		char_request = NO;
		line_request = NO;
		char_request_uni = NO;
		line_request_uni = NO;
		echo_line_input = YES;
		//terminate_line_input = 0;
		style = style_Normal;
		
		self.stream = [[[GlkStreamWindow alloc] initWithWindow:self] autorelease];
		self.echostream = nil;
		
		styleset = nil;
		[library.windows addObject:self];
		
		if (library.dispatch_register_obj)
			disprock = (*library.dispatch_register_obj)(self, gidisp_Class_Window);
	}
	
	return self;
}

- (void) dealloc {
	NSLog(@"GlkWindow dealloc %x", self);
	
	if (inlibrary)
		[NSException raise:@"GlkException" format:@"GlkWindow reached dealloc while in library"];
	if (!type)
		[NSException raise:@"GlkException" format:@"GlkWindow reached dealloc with type unset"];
	type = 0;
	if (!tag)
		[NSException raise:@"GlkException" format:@"GlkWindow reached dealloc with tag unset"];
	self.tag = nil;
	
	self.stream = nil;
	self.echostream = nil;
	self.parent = nil;
	
	self.styleset = nil;
	self.library = nil;

	[super dealloc];
}

/* Close a window, and perhaps its subwindows too. 
*/
- (void) windowCloseRecurse:(BOOL)recurse {
	/* We don't want this object to evaporate in the middle of this method. */
	[[self retain] autorelease];
	
	//### subclasses: gidispa unregister inbuf
	
	for (GlkWindowPair *wx=self.parent; wx; wx=wx.parent) {
		if (wx.type == wintype_Pair) {
			if (wx.key == self) {
				wx.key = nil;
				wx.keydamage = YES;
			}
		}
	}
	
	if (recurse && type == wintype_Pair) {
		GlkWindowPair *pwx = (GlkWindowPair *)self;
		if (pwx.child1)
			[pwx.child1 windowCloseRecurse:YES];
		if (pwx.child2)
			[pwx.child2 windowCloseRecurse:YES];
	}

	if (library.dispatch_unregister_obj)
		(*library.dispatch_unregister_obj)(self, gidisp_Class_Window, disprock);
		
	if (stream) {
		[stream streamDelete];
		self.stream = nil;
	}
	self.echostream = nil;
	self.parent = nil;
	
	if (![library.windows containsObject:self])
		[NSException raise:@"GlkException" format:@"GlkWindow was not in library windows list"];
	[library.windows removeObject:self];
	inlibrary = NO;
}

- (void) getWidth:(glui32 *)widthref height:(glui32 *)heightref {
	*widthref = 0;
	*heightref = 0;
}

/* When a stram is closed, we call this to detach it from any windows who have it as their echostream.
*/
+ (void) unEchoStream:(strid_t)str {
	GlkLibrary *library = [GlkLibrary singleton];
	for (GlkWindow *win in library.windows) {
		if (win.echostream == str)
			win.echostream = nil;
	}
}

/* When a window changes size for any reason -- device rotation, or new windows appearing -- this is invoked. (For pair windows, it's recursive.) The argument is the rectangle that the window is given.
*/
- (void) windowRearrange:(CGRect)box {
	[NSException raise:@"GlkException" format:@"windowRearrange: not implemented"];
}

/*	And now the printing methods. All of this are invoked from the printing methods of GlkStreamWindow.

	Note that putChar, putCString, etc have already been collapsed into putBuffer and putUBuffer calls. The text window classes only have to customize those. (The non-text windows just ignore them.)
*/

- (void) putBuffer:(char *)buf len:(glui32)len {
}

- (void) putUBuffer:(glui32 *)buf len:(glui32)len {
}

/* For non-text windows, we do nothing. The text window classes will override this method.*/
- (void) clearWindow {
}


@end


@implementation GlkWindowBuffer
/* GlkWindowBuffer: a textbuffer window. */

@synthesize updatetext;

- (id) initWithType:(glui32)wintype rock:(glui32)winrock {
	self = [super initWithType:wintype rock:winrock];
	
	if (self) {
		self.updatetext = [NSMutableArray arrayWithCapacity:32];
	}
	
	return self;
}

- (void) dealloc {
	self.updatetext = nil;
	[super dealloc];
}

- (void) windowRearrange:(CGRect)box {
	bbox = box;
	//### count on-screen lines, maybe
}

- (void) getWidth:(glui32 *)widthref height:(glui32 *)heightref {
	*widthref = 0;
	*heightref = 0;
	//### count on-screen lines, maybe
}

- (void) putBuffer:(char *)buf len:(glui32)len {
	if (!len)
		return;
	
	/* Turn the buffer into an NSString. We'll release this at the end of the function. */
	NSString *str = [[NSString alloc] initWithBytes:buf length:len encoding:NSISOLatin1StringEncoding];
	[self putString:str];	
	[str release];
}

- (void) putUBuffer:(glui32 *)buf len:(glui32)len {
	if (!len)
		return;
	
	/* Turn the buffer into an NSString. We'll release this at the end of the function. 
		This is an endianness dependency; we're telling NSString that our array of 32-bit words in stored little-endian. (True for all iOS, as I write this.) */
	NSString *str = [[NSString alloc] initWithBytes:buf length:len*sizeof(glui32) encoding:NSUTF32LittleEndianStringEncoding];
	[self putString:str];	
	[str release];
}

/* Break the string up into GlkStyledLines. When the GlkWinBufferView updates, it will pluck these out and make use of them.
*/
- (void) putString:(NSString *)str {
	NSArray *linearr = [str componentsSeparatedByCharactersInSet:newlineCharSet];
	BOOL isfirst = YES;
	for (NSString *ln in linearr) {
		if (isfirst) {
			isfirst = NO;
		}
		else {
			/* The very first line was a paragraph continuation, but this is a succeeding line, so it's the start of a new paragraph. */
			GlkStyledLine *sln = [[[GlkStyledLine alloc] initWithStatus:linestat_NewLine] autorelease];
			[updatetext addObject:sln];
		}
		
		if (ln.length == 0) {
			/* This line has no content. (We've already added the new paragraph.) */
			continue;
		}
		
		GlkStyledLine *lastsln = [updatetext lastObject];
		if (!lastsln) {
			lastsln = [[[GlkStyledLine alloc] initWithStatus:linestat_Continue] autorelease];
			[updatetext addObject:lastsln];
		}
		
		GlkStyledString *laststr = [lastsln.arr lastObject];
		if (laststr && laststr.style == style) {
			[laststr appendString:ln];
		}
		else {
			GlkStyledString *newstr = [[[GlkStyledString alloc] initWithText:ln style:style] autorelease];
			[lastsln.arr addObject:newstr];
		}
	}
}

- (void) clearWindow {
	//###
}

@end


@implementation GlkWindowGrid
/* GlkWindowGrid: a textgrid window. */

@synthesize lines;
@synthesize width;
@synthesize height;

- (id) initWithType:(glui32)wintype rock:(glui32)winrock {
	self = [super initWithType:wintype rock:winrock];
	
	if (self) {
		width = 0;
		height = 0;
		curx = 0;
		cury = 0;
		
		self.lines = [NSMutableArray arrayWithCapacity:8];
	}
	
	return self;
}

- (void) dealloc {
	self.lines = nil;
	[super dealloc];
}

- (void) windowRearrange:(CGRect)box {
	bbox = box;
	
	int newwidth = ((bbox.size.width-styleset.marginframe.size.width) / styleset.charbox.width);
	int newheight = ((bbox.size.height-styleset.marginframe.size.height) / styleset.charbox.height);
	if (newwidth < 0)
		newwidth = 0;
	if (newheight < 0)
		newheight = 0;
		
	width = newwidth;
	height = newheight;
	
	NSLog(@"grid window now %dx%d", width, height);
	
	while (lines.count > height)
		[lines removeLastObject];
	while (lines.count < height)
		[lines addObject:[[[GlkGridLine alloc] init] autorelease]];
		
	for (GlkGridLine *ln in lines)
		[ln setWidth:width];
}

- (void) getWidth:(glui32 *)widthref height:(glui32 *)heightref {
	*widthref = width;
	*heightref = height;
}

- (void) moveCursorToX:(glui32)xpos Y:(glui32)ypos {
	/* Don't worry about large numbers, or numbers that the caller might have thought were negative. The canonicalization will fix this. */
	if (xpos > 0x7FFF)
		xpos = 0x7FFF;
	if (ypos > 0x7FFF)
		ypos = 0x7FFF;
		
	curx = xpos;
	cury = ypos;
}

- (void) clearWindow {
	for (GlkGridLine *ln in lines) {
		[ln clear];
	}
}

- (void) putBuffer:(char *)buf len:(glui32)len {
	for (int ix=0; ix<len; ix++)
		[self putUChar:(unsigned char)(buf[ix])];
}

- (void) putUBuffer:(glui32 *)buf len:(glui32)len {
	for (int ix=0; ix<len; ix++)
		[self putUChar:buf[ix]];
}

- (void) putUChar:(glui32)ch {
	/* Canonicalize the cursor position. That is, the cursor may have been left outside the window area, or may be too close to the edge to print the next character. Wrap it if necessary. */
	if (curx < 0)
		curx = 0;
	else if (curx >= width) {
		curx = 0;
		cury++;
	}
	if (cury < 0)
		cury = 0;
	else if (cury >= height)
		return; /* outside the window */

	if (ch == '\n') {
		/* a newline just moves the cursor. */
		cury++;
		curx = 0;
		return;
	}
	
	GlkGridLine *ln = [lines objectAtIndex:cury];
	ln.chars[curx] = ch;
	ln.styles[curx] = style;
	ln.dirty = YES;
	
	curx++;
	
	/* We can leave the cursor outside the window, since it will be canonicalized next time a character is printed. */
}

@end


@implementation GlkWindowPair
/* GlkWindowPair: a pair window (the kind of window that has subwindows). */

@synthesize dir;
@synthesize division;
@synthesize key;
@synthesize keydamage;
@synthesize size;
@synthesize hasborder;
@synthesize vertical;
@synthesize backward;
@synthesize child1;
@synthesize child2;

/* GlkWindowPair gets a special initializer. (Only called from glk_window_open() when a window is split.)
*/
- (id) initWithMethod:(glui32)method keywin:(GlkWindow *)keywin size:(glui32)initsize {
	self = [super initWithType:wintype_Pair rock:0];
	
	if (self) {
		dir = method & winmethod_DirMask;
		division = method & winmethod_DivisionMask;
		hasborder = ((method & winmethod_BorderMask) == winmethod_Border);
		self.key = keywin;
		keydamage = FALSE;
		size = initsize;

		vertical = (dir == winmethod_Left || dir == winmethod_Right);
		backward = (dir == winmethod_Left || dir == winmethod_Above);

		self.child1 = nil;
		self.child2 = nil;
	}
	
	return self;
}

- (void) dealloc {
	self.key = nil;
	self.child1 = nil;
	self.child2 = nil;
	[super dealloc];
}

/* For a pair window, the task is to figure out how to divide the box between its children. Then recursively call windowRearrange on them.
*/
- (void) windowRearrange:(CGRect)box {
	CGFloat min, max, diff;
	
	bbox = box;

	if (vertical) {
		min = bbox.origin.x;
		max = min + bbox.size.width;
		splitwid = 4; //content_metrics.inspacingx;
	}
	else {
		min = bbox.origin.y;
		max = min + bbox.size.height;
		splitwid = 4; //content_metrics.inspacingy;
	}
	if (!hasborder)
		splitwid = 0;
	diff = max - min;

	if (division == winmethod_Proportional) {
		split = floorf((diff * size) / 100.0);
	}
	else if (division == winmethod_Fixed) {
		split = 0;
		if (key && key.type == wintype_TextBuffer) {
			if (!vertical)
				split = (size * key.styleset.charbox.height + key.styleset.marginframe.size.height);
			else
				split = (size * key.styleset.charbox.width + key.styleset.marginframe.size.width);
		}
		if (key && key.type == wintype_TextGrid) {
			if (!vertical)
				split = (size * key.styleset.charbox.height + key.styleset.marginframe.size.height);
			else
				split = (size * key.styleset.charbox.width + key.styleset.marginframe.size.width);
		}
		split = ceilf(split);
	}
	else {
		/* default behavior for unknown division method */
		split = floorf(diff / 2);
	}

	/* Split is now a number between 0 and diff. Convert that to a number
	   between min and max; also apply upside-down-ness. */
	if (!backward) {
		split = max-split-splitwid;
	}
	else {
		split = min+split;
	}

	/* Make sure it's really between min and max. */
	if (min >= max) {
		split = min;
	}
	else {
		split = fminf(fmaxf(split, min), max-splitwid);
	}
	
	CGRect box1 = bbox;
	CGRect box2 = bbox;

	if (vertical) {
		box1.size.width = split - bbox.origin.x;
		box2.origin.x = split + splitwid;
		box2.size.width = (bbox.origin.x+bbox.size.width) - box2.origin.x;
	}
	else {
		box1.size.height = split - bbox.origin.y;
		box2.origin.y = split + splitwid;
		box2.size.height = (bbox.origin.y+bbox.size.height) - box2.origin.y;
	}
	
	GlkWindow *ch1, *ch2;

	if (!backward) {
		ch1 = child1;
		ch2 = child2;
	}
	else {
		ch1 = child2;
		ch2 = child1;
	}

	[ch1 windowRearrange:box1];
	[ch2 windowRearrange:box2];
}

@end


