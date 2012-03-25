/* GlkWinBufferView.m: Glk textbuffer window view
	for IosGlk, the iOS implementation of the Glk API.
	Designed by Andrew Plotkin <erkyrath@eblong.com>
	http://eblong.com/zarf/glk/
*/

#import "GlkWinBufferView.h"
#import "IosGlkAppDelegate.h"
#import "IosGlkViewController.h"
#import "GlkLibrary.h"
#import "GlkWindowState.h"
#import "GlkLibraryState.h"
#import "GlkUtilTypes.h"

#import "CmdTextField.h"
#import "StyledTextView.h"
#import "MoreBoxView.h"
#import "StyleSet.h"
#import "GlkUtilities.h"

@implementation GlkWinBufferView

@synthesize textview;
@synthesize moreview;
@synthesize nowcontentscrolling;

- (id) initWithWindow:(GlkWindowState *)winref frame:(CGRect)box {
	self = [super initWithWindow:winref frame:box];
	if (self) {
		lastLayoutBounds = CGRectNull;
		self.textview = [[[StyledTextView alloc] initWithFrame:self.bounds styles:styleset] autorelease];
		//textview.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		textview.delegate = self;
		[self addSubview:textview];
		
		IosGlkViewController *glkviewc = [IosGlkViewController singleton];
		
		self.moreview = [[[MoreBoxView alloc] initWithFrame:CGRectZero] autorelease];
		[glkviewc buildMoreView:moreview];
		CGRect rect = moreview.frameview.frame;
		rect.origin.x = box.size.width - rect.size.width - 4;
		rect.origin.y = box.size.height - rect.size.height - 4;
		moreview.frame = rect;
		[moreview addSubview:moreview.frameview];
		moreview.userInteractionEnabled = NO;
		moreview.hidden = YES;
		[self addSubview:moreview];		
	}
	return self;
}

- (void) dealloc {
	textview.delegate = nil;
	self.textview = nil;
	self.moreview = nil;
	[super dealloc];
}

/* This is called when the GlkFrameView changes size, and also (in iOS4) when the child scrollview scrolls. This is a mysterious mix of cases, but we can safely ignore the latter by only acting when the bounds actually change. 
*/
- (void) layoutSubviews {
	[super layoutSubviews];

	if (CGRectEqualToRect(lastLayoutBounds, self.bounds)) {
		return;
	}
	lastLayoutBounds = self.bounds;
	NSLog(@"WBV: layoutSubviews to %@", StringFromRect(self.bounds));
	
	CGRect rect = moreview.frameview.frame;
	rect.origin.x = lastLayoutBounds.size.width - rect.size.width - 4;
	rect.origin.y = lastLayoutBounds.size.height - rect.size.height - 4;
	moreview.frame = rect;
	
	textview.frame = lastLayoutBounds;
	[textview setNeedsLayout];
}

- (void) uncacheLayoutAndStyles {
	[textview acceptStyleset:styleset];
	if (inputfield)
		[inputfield adjustForWindowStyles:styleset];
	lastLayoutBounds = CGRectNull;
	[textview uncacheLayoutAndVLines:YES];
}

- (void) updateFromWindowState {
	GlkWindowBufferState *bufwin = (GlkWindowBufferState *)winstate;
	
	NSLog(@"WBV: updateFromWindowState: %d lines (dirty %d to %d)", bufwin.lines.count, bufwin.linesdirtyfrom, bufwin.linesdirtyto);
	if (bufwin.linesdirtyfrom >= bufwin.linesdirtyto)
		return;
	
	[textview updateWithLines:bufwin.lines dirtyFrom:bufwin.linesdirtyfrom clearCount:bufwin.clearcount refresh:bufwin.library.everythingchanged];
	[textview setNeedsDisplay];
}

/* This is invoked whenever the user types something. If we're at a "more" prompt, it pages down once, and returns YES. Otherwise, it pages all the way to the bottom and returns NO.
 */
- (BOOL) pageDownOnInput {
	if (textview.moreToSee) {
		[textview pageDown];
		return YES;
	}
	
	[textview pageToBottom];
	return NO;
}

- (void) setMoreFlag:(BOOL)flag {
	if (morewaiting == flag)
		return;
	
	morewaiting = flag;
	if (flag) {
		if ([IosGlkAppDelegate animblocksavailable]) {
			moreview.alpha = 0;
			moreview.hidden = NO;
			[UIView animateWithDuration:0.2 
							 animations:^{ moreview.alpha = 1; } ];
		}
		else {
			moreview.hidden = NO;
		}
	}
	else {
		if ([IosGlkAppDelegate animblocksavailable]) {
			[UIView animateWithDuration:0.2 
							 animations:^{ moreview.alpha = 0; }
							 completion:^(BOOL finished) { moreview.hidden = YES; } ];
		}
		else {
			moreview.hidden = YES;
		}
	}
	
	nowcontentscrolling = NO;
}

/* Either the text field is brand-new, or last cycle's text field needs to be adjusted for a new request. Add it as a subview of the textview (if necessary), and move it to the right place.
*/
- (void) placeInputField:(UITextField *)field holder:(UIScrollView *)holder {
	CGRect box = [textview placeForInputField];
	//NSLog(@"WBV: input field goes to %@", StringFromRect(box));
	
	field.frame = CGRectMake(0, 0, box.size.width, box.size.height);
	holder.contentSize = box.size;
	holder.frame = box;
	if (!holder.superview)
		[textview addSubview:holder];
}

/* UIScrollView delegate methods: */

- (void) scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
	if (nowcontentscrolling && textview.moreToSee)
		[self setMoreFlag:YES];
	if (textview.anySelection)
		[textview showSelectionMenu];
}

- (void) scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
	if (!decelerate) {
		if (textview.anySelection)
			[textview showSelectionMenu];
	}
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
	if (textview.anySelection)
		[textview showSelectionMenu];
}

@end
