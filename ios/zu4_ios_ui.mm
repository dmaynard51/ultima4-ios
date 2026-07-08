/*
 *  zu4_ios_ui.mm
 *  On-screen touch controls for the iOS port of zu4 (Ultima IV). A native UIKit
 *  overlay of buttons — a movement D-pad plus a few action keys and a keyboard
 *  toggle — sits over the SDL view. Each button synthesises the SDL key event
 *  the engine expects. U4's other commands are single letters, typed via the
 *  on-screen keyboard (the ⌨ button).
 */
#import <UIKit/UIKit.h>

#include "zu4_ios_ui.h"
#include "SDL.h"
#include "SDL_syswm.h"

// Special tag value meaning "toggle the on-screen keyboard" rather than a key.
#define ZU4_TAG_KEYBOARD 0x7FFFFFFF

static void zu4_push_key(SDL_Keycode sym)
{
	SDL_Event e;
	SDL_zero(e);
	e.type = SDL_KEYDOWN;
	e.key.state = SDL_PRESSED;
	e.key.keysym.sym = sym;
	e.key.keysym.scancode = SDL_GetScancodeFromKey(sym);
	SDL_PushEvent(&e);

	e.type = SDL_KEYUP;
	e.key.state = SDL_RELEASED;
	SDL_PushEvent(&e);
}

// Shared state (declared up-front so the button target class can use it).
static bool g_ui_installed = false;
static SDL_Window *g_window = NULL;
static UIView *g_root_view = nil;   // the SDL view (fills the window)
static CGRect g_full_frame;         // its normal, full-screen frame
static UIView *g_overlay = nil;     // non-scaled button layer (sibling of the SDL view)
static bool g_kb_shown = false;     // our own record of keyboard visibility (SDL's flag desyncs)

// A transparent overlay that holds the buttons but lets touches on empty areas fall through
// to the game view below (so tapping the map still works). It lives on the UIWindow — NOT
// inside the SDL view — so the keyboard-scale transform never resizes the buttons.
@interface Zu4PassthroughView : UIView
@end
@implementation Zu4PassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
	UIView *hit = [super hitTest:point withEvent:event];
	return hit == self ? nil : hit;   // empty area -> pass through to the game view
}
@end

@interface Zu4ButtonTarget : NSObject
- (void)onTap:(UIButton *)sender;
- (void)keyboardWillShow:(NSNotification *)note;
- (void)keyboardWillHide:(NSNotification *)note;
@end

@implementation Zu4ButtonTarget
- (void)onTap:(UIButton *)sender
{
	if(sender.tag == ZU4_TAG_KEYBOARD) {
		zu4_ios_toggle_keyboard();
		return;
	}
	zu4_push_key((SDL_Keycode)sender.tag);
}

// When the keyboard appears, scale the whole game down into the space above it
// so nothing is cropped; restore full size when it hides. SDL rewrites its
// view's .frame in its own keyboard handler, so we defer with dispatch_async
// (to run after SDL) and reset transform + frame to a known-good state first.
- (void)applyKeyboardScale:(CGFloat)scale
{
	if(g_root_view == nil)
		return;
	g_root_view.transform = CGAffineTransformIdentity;
	g_root_view.frame = g_full_frame;
	if(scale < 1.0) {
		CGFloat H = g_full_frame.size.height;
		g_root_view.transform = CGAffineTransformConcat(
		    CGAffineTransformMakeScale(scale, scale),
		    CGAffineTransformMakeTranslation(0, -H * (1.0 - scale) / 2.0));
	}
}

- (void)keyboardWillShow:(NSNotification *)note
{
	if(g_root_view == nil)
		return;
	CGRect kb = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	CGRect kbLocal = [g_root_view convertRect:kb fromView:nil];
	CGFloat H = g_full_frame.size.height;
	CGFloat visibleH = kbLocal.origin.y;   // keyboard top, in view coords
	if(H < 1.0 || visibleH < 120.0)
		return;
	CGFloat s = visibleH / H;
	dispatch_async(dispatch_get_main_queue(), ^{
		[self applyKeyboardScale:s];
		// Shrink and lift the button overlay so the buttons sit just above the
		// keyboard without the top button riding too high.
		if(g_overlay) {
			const CGFloat k = 0.7;
			CGFloat lift = H * 0.5 * (1.0 + k) - visibleH;
			g_overlay.transform = CGAffineTransformConcat(
			    CGAffineTransformMakeScale(k, k),
			    CGAffineTransformMakeTranslation(0, -lift));
		}
	});
}

- (void)keyboardWillHide:(NSNotification *)note
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self applyKeyboardScale:1.0];
		if(g_overlay)
			g_overlay.transform = CGAffineTransformIdentity;
	});
}
@end

// Retain the target for the lifetime of the app so the button actions fire.
static Zu4ButtonTarget *g_btn_target = nil;

void zu4_ios_show_keyboard(int show)
{
	if(show) {
		if(!SDL_IsTextInputActive())
			SDL_StartTextInput();
		g_kb_shown = true;
	} else {
		if(SDL_IsTextInputActive())
			SDL_StopTextInput();
		g_kb_shown = false;
	}
}

void zu4_ios_toggle_keyboard(void)
{
	// Track our own state, not SDL_IsTextInputActive() (a cold StartTextInput
	// sets the SDL flag without presenting the keyboard, which desyncs the toggle).
	zu4_ios_show_keyboard(g_kb_shown ? 0 : 1);
}

static UIButton *zu4_make_button(NSString *title, long tag, CGRect frame,
                                 Zu4ButtonTarget *target)
{
	UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
	b.frame = frame;
	[b setTitle:title forState:UIControlStateNormal];
	b.titleLabel.font = [UIFont boldSystemFontOfSize:(title.length > 2 ? 15 : 22)];
	b.titleLabel.adjustsFontSizeToFitWidth = YES;
	[b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	b.backgroundColor = [UIColor colorWithWhite:0.20 alpha:0.55];
	b.layer.cornerRadius = 8.0;
	b.layer.borderWidth = 1.0;
	b.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
	b.tag = tag;
	b.showsTouchWhenHighlighted = YES;
	[b addTarget:target action:@selector(onTap:)
	    forControlEvents:UIControlEventTouchDown];
	return b;
}

void zu4_ios_setup_ui(SDL_Window *window)
{
	if(g_ui_installed || window == NULL)
		return;

	SDL_SysWMinfo info;
	SDL_VERSION(&info.version);
	if(!SDL_GetWindowWMInfo(window, &info))
		return;

	UIWindow *uiwin = info.info.uikit.window;
	UIViewController *vc = uiwin.rootViewController;
	UIView *root = vc.view;
	if(root == nil)
		return;

	g_ui_installed = true;
	g_window = window;
	g_root_view = root;
	g_full_frame = root.frame;
	g_btn_target = [[Zu4ButtonTarget alloc] init];
	Zu4ButtonTarget *t = g_btn_target;

	[[NSNotificationCenter defaultCenter] addObserver:t
	    selector:@selector(keyboardWillShow:)
	    name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:t
	    selector:@selector(keyboardWillHide:)
	    name:UIKeyboardWillHideNotification object:nil];

	// Transparent, non-scaled button overlay on the window (not the SDL view).
	g_overlay = [[Zu4PassthroughView alloc] initWithFrame:uiwin.bounds];
	g_overlay.backgroundColor = [UIColor clearColor];
	g_overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[uiwin addSubview:g_overlay];

	CGRect b = root.bounds;
	UIEdgeInsets safe = root.safeAreaInsets;
	CGFloat left = b.origin.x + safe.left;
	CGFloat right = b.origin.x + b.size.width - safe.right;
	CGFloat bottom = b.origin.y + b.size.height - safe.bottom;

	const CGFloat DS = 52.0;  // d-pad button size (bigger for easier movement)
	const CGFloat S = 48.0;   // action button size
	const CGFloat G = 5.0;    // gap

	// ---- Left side: movement D-pad, anchored bottom-left ----
	CGFloat dpx = left + 6.0;
	CGFloat dpy = bottom - (DS * 3 + G * 2) - 10.0;
	[g_overlay addSubview:zu4_make_button(@"▲", SDLK_UP,
	         CGRectMake(dpx + DS + G, dpy, DS, DS), t)];
	[g_overlay addSubview:zu4_make_button(@"◀", SDLK_LEFT,
	         CGRectMake(dpx, dpy + DS + G, DS, DS), t)];
	[g_overlay addSubview:zu4_make_button(@"▶", SDLK_RIGHT,
	         CGRectMake(dpx + (DS + G) * 2, dpy + DS + G, DS, DS), t)];
	[g_overlay addSubview:zu4_make_button(@"▼", SDLK_DOWN,
	         CGRectMake(dpx + DS + G, dpy + (DS + G) * 2, DS, DS), t)];

	// ---- Right side: action buttons, stacked bottom-right ----
	// U4's commands are all typed letters, so the keyboard button is primary.
	NSArray *labels = @[ @"⌨", @"Esc", @"↵", @"Spc" ];
	long tags[] = { ZU4_TAG_KEYBOARD, SDLK_ESCAPE, SDLK_RETURN, SDLK_SPACE };
	int n = 4;
	CGFloat bx = right - S - 8.0;
	CGFloat by = bottom - (S * n + G * (n - 1)) - 10.0;
	for(int i = 0; i < n; i++) {
		[g_overlay addSubview:zu4_make_button(labels[i], tags[i],
		         CGRectMake(bx, by + (S + G) * i, S, S), t)];
	}

	// Pre-warm SDL's text-input responder so the FIRST keyboard tap presents it
	// on a single press.
	dispatch_async(dispatch_get_main_queue(), ^{
		SDL_StartTextInput();
		SDL_StopTextInput();
		g_kb_shown = false;
	});
}
