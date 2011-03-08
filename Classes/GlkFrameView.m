/* GlkFrameView.m: Main view class
	for IosGlk, the iOS implementation of the Glk API.
	Designed by Andrew Plotkin <erkyrath@eblong.com>
	http://eblong.com/zarf/glk/
*/

/*	GlkFrameView is the UIView which contains all of the Glk windows. (The GlkWindowViews are its children.) It is responsible for getting them all updated properly when the VM blocks for UI input.

	It's worth noting that all the content-y Glk windows have corresponding GlkWindowViews. But pair windows don't. They are abstractions which exist solely to calculate child window sizes.
*/

#import "GlkFrameView.h"
#import "GlkWindowView.h"
#import "GlkWinBufferView.h"
#import "GlkAppWrapper.h"
#import "GlkLibrary.h"
#import "GlkWindow.h"
#import "GlkUtilTypes.h"
#include "GlkUtilities.h"

@implementation GlkFrameView

@synthesize windowviews;

- (void) awakeFromNib {
	[super awakeFromNib];
	NSLog(@"GlkFrameView awakened, bounds %@", StringFromRect(self.bounds));
	
	keyboardHeight = 0.0;
	self.windowviews = [NSMutableDictionary dictionaryWithCapacity:8];
}

- (void) dealloc {
	self.windowviews = nil;
	[super dealloc];
}

- (CGFloat) keyboardHeight {
	return keyboardHeight;
}

- (void) setKeyboardHeight:(CGFloat)val {
	keyboardHeight = val;
	[self setNeedsLayout];
}

- (void) layoutSubviews {
	NSLog(@"frameview layoutSubviews");
	
	CGRect box = self.bounds;
	box.size.height -= keyboardHeight;
	if (box.size.height < 0)
		box.size.height = 0;
	[[GlkAppWrapper singleton] setFrameSize:box];
}

/* This tells all the window views to get up to date with the new output in their data (GlkWindow) objects. If window views have to be created or destroyed (because GlkWindows have opened or closed), this does that too.
*/
- (void) updateFromLibraryState:(GlkLibrary *)library {
	NSLog(@"updateFromLibraryState: %@", StringFromRect(library.bounds));
	
	if (!library)
		[NSException raise:@"GlkException" format:@"updateFromLibraryState: no library"];
	
	/* Build a list of windowviews which need to be closed. */
	NSMutableDictionary *closed = [NSMutableDictionary dictionaryWithDictionary:windowviews];
	for (GlkWindow *win in library.windows) {
		[closed removeObjectForKey:win.tag];
	}

	/* And close them. */
	for (NSNumber *tag in closed) {
		GlkWindowView *winv = [closed objectForKey:tag];
		[winv removeFromSuperview];
		winv.textfield = nil; /* detach this now */
		//### probably should detach all subviews
		[windowviews removeObjectForKey:tag];
	}
	
	closed = nil;
	
	/* If there are any new windows, create windowviews for them. */
	for (GlkWindow *win in library.windows) {
		if (win.type != wintype_Pair && ![windowviews objectForKey:win.tag]) {
			GlkWindowView *winv = [GlkWindowView viewForWindow:win];
			[windowviews setObject:winv forKey:win.tag];
			[self addSubview:winv];
		}
	}
	
	/*
	NSLog(@"frameview has %d windows:", windowviews.count);
	for (NSNumber *tag in windowviews) {
		NSLog(@"... %d: %@", [tag intValue], [windowviews objectForKey:tag]);
		//GlkWindowView *winv = [windowviews objectForKey:tag];
		//NSLog(@"... win is %@", winv.win);
	}
	*/

	/* Now go through all the window views, and tell them to update to match their windows. */
	for (NSNumber *tag in windowviews) {
		GlkWindowView *winv = [windowviews objectForKey:tag];
		[winv updateFromWindowState];
		[winv updateFromWindowInputs];
	}
}

/* This tells all the window views to get up to date with the sizes of their GlkWindows. The library's setMetrics must already have been called, to get the GlkWindow sizes set right.
*/
- (void) updateFromLibrarySize:(GlkLibrary *)library {
	NSLog(@"updateFromLibrarySize: %@", StringFromRect(library.bounds));
	
	for (NSNumber *tag in windowviews) {
		GlkWindowView *winv = [windowviews objectForKey:tag];
		[winv updateFromWindowSize];
		// This is part of the terrible layout system.
		if ([winv isKindOfClass:[GlkWinBufferView class]])
			((GlkWinBufferView *)winv).scrollDownNextLayout = YES;
		[winv setNeedsLayout]; // This is too.
	}
	[[GlkAppWrapper singleton] acceptEventType:evtype_Arrange window:nil val1:0 val2:0];
}

/* This is invoked in the main thread, by the VM thread, which is waiting on the result. We're safe from deadlock because the VM thread can't be in glk_select(); it can't be holding the iowait lock, and it can't get into the code path that rearranging the view structure.
*/
- (void) editingTextForWindow:(GlkTagString *)tagstring {
	GlkWindowView *winv = [windowviews objectForKey:tagstring.tag];
	if (!winv)
		return;
	
	UITextField *textfield = winv.textfield;
	if (!textfield)
		return;
		
	NSString *text = textfield.text;
	if (!text)
		return;
	
	/* The VM thread, when it picks this up, will take over the retention. */
	tagstring.str = [[NSString stringWithString:text] retain];
}

@end
