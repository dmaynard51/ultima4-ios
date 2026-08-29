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
static UIView *g_overlay = nil;     // non-scaled button layer (sibling of the SDL view)
static UIView *g_dpad = nil;        // movement D-pad container
static bool g_kb_shown = false;     // our own record of keyboard visibility (SDL's flag desyncs)
static bool g_portrait = false;     // true while the device is in a portrait orientation
static CGFloat g_kb_height = 0;     // last known keyboard height in points, 0 = never observed
static bool g_kb_height_portrait = false; // which orientation g_kb_height was measured in

// Portrait's D-pad/Esc sit in a strip of their own above the keyboard (two
// D-pad rows plus margins, ~140pt), so the game canvas's height budget there
// is the space above that strip. Landscape doesn't need this: its shrunk
// game view frees up side margins wide enough for its buttons already.
static const CGFloat ZU4_PORTRAIT_BUTTON_RESERVE = 140.0;

// The letterboxed 320x200 game art's aspect ratio, used to find where the
// art sits within the canvas: portrait letterboxes it with blank bars top
// and bottom, landscape fills the full height.
static const CGFloat ZU4_GAME_ASPECT = 320.0 / 200.0;

// A transparent overlay that holds the buttons but lets touches on empty areas fall through
// to the game view below (so tapping the map still works). It lives on the UIWindow — NOT
// inside the SDL view — so the keyboard-scale transform never resizes the buttons.
static void zu4_quiet_keyboard(void);   // defined below; used by keyboardWillShow

@interface Zu4PassthroughView : UIView
@end
@implementation Zu4PassthroughView
// Return YES so hitTest still recurses into subviews (buttons) even when they've
// been transformed outside this view's own bounds. Passthrough is preserved by
// hitTest below (empty areas still resolve to self and are dropped).
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
	return YES;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
	UIView *hit = [super hitTest:point withEvent:event];
	return (hit == self) ? nil : hit;   // empty area -> pass through to the game view
}
@end

@interface Zu4ButtonTarget : NSObject
- (void)onTap:(UIButton *)sender;
- (void)keyboardWillShow:(NSNotification *)note;
- (void)keyboardWillHide:(NSNotification *)note;
- (void)handleRotation:(BOOL)portrait size:(CGSize)size;
- (void)applyLayoutForSize:(CGSize)size keyboardHeight:(CGFloat)kbHeight;
@end

// Forward declaration; defined below, used by Zu4ButtonTarget's applyLayoutForSize:.
static UIButton *zu4_make_button(NSString *title, long tag, CGRect frame,
                                 Zu4ButtonTarget *target);

@implementation Zu4ButtonTarget
- (void)onTap:(UIButton *)sender
{
	if(sender.tag == ZU4_TAG_KEYBOARD) {
		zu4_ios_toggle_keyboard();
		return;
	}
	zu4_push_key((SDL_Keycode)sender.tag);
}

// The single place that computes and applies the entire layout -- the game
// view's scale/position and every button's position -- from exactly two
// inputs: the window's current size and the keyboard's current height (0 if
// not shown). Takes no state from anywhere else, so the result depends only
// on the (size, kbHeight) pair the caller passes in, never a mix of values
// cached at different times by different callers.
- (void)applyLayoutForSize:(CGSize)size keyboardHeight:(CGFloat)kbHeight
{
	if(g_root_view == nil || g_overlay == nil)
		return;

	CGFloat W = size.width, H = size.height;
	BOOL portrait = H > W;
	CGRect fullFrame = CGRectMake(0, 0, W, H);
	CGFloat keyboardTop = (kbHeight > 0.0) ? H - kbHeight : 0.0;

	// The game canvas's height budget: in portrait, above the button strip
	// (not just above the keyboard); in landscape, just above the keyboard.
	CGFloat availableHeight = keyboardTop;
	if(portrait && availableHeight > 0.0)
		availableHeight -= ZU4_PORTRAIT_BUTTON_RESERVE;

	// Defaults -- full size, nothing cropped -- used whenever the keyboard
	// isn't currently shown/known, or the budget above has collapsed to
	// nothing; the safe fallback is the full uncropped canvas, not an
	// inverted or negative layout.
	CGFloat scale = 1.0, artTop = 0.0, bottomTarget = H;
	if(keyboardTop > 0.0 && availableHeight > 0.0) {
		if(portrait) {
			// Where the letterboxed art sits within the canvas: SDL fits it
			// to the full width here, leaving blank bars top and bottom.
			CGFloat artH = (W / H > ZU4_GAME_ASPECT) ? H : W / ZU4_GAME_ASPECT;
			artTop = (H - artH) / 2.0;
			scale = (availableHeight < artH) ? availableHeight / artH : 1.0;
		} else {
			// Landscape's art already fills the full height (artTop stays 0).
			scale = (availableHeight < H) ? availableHeight / H : 1.0;
		}
		bottomTarget = availableHeight;
	}

	// Apply the game view's scale, anchored so the ART's bottom edge lands on
	// bottomTarget (rather than top-anchoring the whole canvas, which would
	// waste width and height alike shrinking a blank bar to make room for
	// nothing). Any slack between the scaled art and bottomTarget becomes
	// extra blank margin at the top instead. At the defaults above (scale 1,
	// artTop 0, bottomTarget == H) this is an identity transform.
	g_root_view.transform = CGAffineTransformIdentity;
	g_root_view.frame = fullFrame;
	CGFloat artHFull = H - 2.0 * artTop;
	CGFloat translate = bottomTarget - H / 2.0 - scale * artHFull / 2.0;
	g_root_view.transform = CGAffineTransformConcat(
	    CGAffineTransformMakeScale(scale, scale),
	    CGAffineTransformMakeTranslation(0, translate));

	// Buttons: rebuilt at their final absolute positions in one pass; no
	// separate transform is layered on afterward.
	[g_overlay.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

	UIEdgeInsets safe = g_root_view.safeAreaInsets;
	CGFloat right = W - safe.right;
	CGFloat screenBottom = H - safe.bottom;
	// Anchor above the keyboard when it's shown (landscape included: its
	// buttons overlay the side margins the shrunk art leaves, so they still
	// need to clear the keyboard vertically); otherwise the plain screen
	// bottom.
	CGFloat bottom = (keyboardTop > 0.0) ? keyboardTop - 8.0 : screenBottom;

	const CGFloat DS = 52.0;  // d-pad button size (bigger for easier movement)
	const CGFloat S = 48.0;   // action button size
	const CGFloat G = 5.0;    // gap

	// ---- Left side: movement D-pad, anchored bottom-left ----
	// Laid out as "◀ [▲ over ▼] ▶" -- three columns, but only two rows tall,
	// to keep the D-pad's footprint compact (particularly important in
	// portrait, where it eats into the limited space above the keyboard).
	CGFloat dpWidth = DS * 3 + G * 2;
	CGFloat dpHeight = DS * 2 + G;
	CGFloat dpy = bottom - dpHeight - 10.0;
	g_dpad = [[Zu4PassthroughView alloc] initWithFrame:CGRectMake(4.0, dpy, dpWidth, dpHeight)];
	g_dpad.backgroundColor = [UIColor clearColor];
	[g_overlay addSubview:g_dpad];
	CGFloat sideY = (dpHeight - DS) / 2.0;   // vertically center left/right against the up/down stack
	[g_dpad addSubview:zu4_make_button(@"◀", SDLK_LEFT,
	         CGRectMake(0, sideY, DS, DS), self)];
	[g_dpad addSubview:zu4_make_button(@"▲", SDLK_UP,
	         CGRectMake(DS + G, 0, DS, DS), self)];
	[g_dpad addSubview:zu4_make_button(@"▼", SDLK_DOWN,
	         CGRectMake(DS + G, DS + G, DS, DS), self)];
	[g_dpad addSubview:zu4_make_button(@"▶", SDLK_RIGHT,
	         CGRectMake((DS + G) * 2, sideY, DS, DS), self)];

	// ---- Right side: action buttons, bottom-right ----
	// In portrait the system keyboard is always up (and provides Return and
	// Space directly), so only Esc (not on any iOS keyboard) earns a button
	// there. Landscape's four buttons use a compact 2x2 grid instead of a
	// 4-tall stack: a stack needs ~4*S+3*G of vertical room, more than fits
	// above a landscape keyboard; the grid only needs 2*S+G.
	if(portrait) {
		CGRect r = CGRectMake(right - S - 8.0, bottom - S - 10.0, S, S);
		[g_overlay addSubview:zu4_make_button(@"Esc", SDLK_ESCAPE, r, self)];
	} else {
		NSArray *labels = @[ @"⌨", @"Esc", @"↵", @"Spc" ];
		long tags[] = { ZU4_TAG_KEYBOARD, SDLK_ESCAPE, SDLK_RETURN, SDLK_SPACE };
		CGFloat gx = right - (S * 2 + G) - 8.0;
		CGFloat gy = bottom - (S * 2 + G) - 10.0;
		for(int i = 0; i < 4; i++) {
			CGFloat x = gx + (i % 2) * (S + G);
			CGFloat y = gy + (i / 2) * (S + G);
			[g_overlay addSubview:zu4_make_button(labels[i], tags[i], CGRectMake(x, y, S, S), self)];
		}
	}
}

- (void)keyboardWillShow:(NSNotification *)note
{
	zu4_quiet_keyboard();   // suppress predictive/suggestion UI
	if(g_root_view == nil || g_root_view.window == nil)
		return;
	// Read the keyboard's own height directly from the notification, and the
	// window's live size, both captured synchronously now rather than
	// inside the deferred block below.
	CGRect kb = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	CGSize winSize = g_root_view.window.bounds.size;
	CGFloat kbH = kb.size.height;
	if(winSize.height < 1.0 || kbH < 20.0 || kbH > winSize.height - 20.0)
		return;
	g_kb_height = kbH;
	g_kb_height_portrait = winSize.height > winSize.width;
	dispatch_async(dispatch_get_main_queue(), ^{
		[self applyLayoutForSize:winSize keyboardHeight:kbH];
	});
}

- (void)keyboardWillHide:(NSNotification *)note
{
	if(g_root_view == nil || g_root_view.window == nil)
		return;
	CGSize winSize = g_root_view.window.bounds.size;
	BOOL portraitNow = winSize.height > winSize.width;
	dispatch_async(dispatch_get_main_queue(), ^{
		if(portraitNow) {
			// The keyboard is meant to stay forced on in portrait -- guard
			// against an incidental system dismiss (e.g. a hardware keyboard
			// attaching, or an iPad dismiss gesture).
			zu4_ios_show_keyboard(1);
			return;
		}
		if(g_kb_shown)
			return;   // a transient hide mid-rotation, not an actual dismiss
		[self applyLayoutForSize:winSize keyboardHeight:0];
	});
}

// Called (deferred, off the SDL window-event watch below) whenever the
// window's size settles after a live rotation.
- (void)handleRotation:(BOOL)portrait size:(CGSize)size
{
	if(g_root_view == nil)
		return;
	BOOL enteringPortrait = portrait && !g_portrait;
	g_portrait = portrait;

	if(enteringPortrait)
		zu4_ios_show_keyboard(1);

	// Only trust the cached keyboard height if it was measured in the
	// orientation we're rotating into -- portrait and landscape keyboards
	// differ substantially in height, and keyboardWillShow (which updates
	// the cache) can fire either before or after this resize event, so
	// orientation match is the reliable signal for whether it still applies.
	CGFloat kbHeight = (g_kb_shown && g_kb_height_portrait == portrait) ? g_kb_height : 0;
	[self applyLayoutForSize:size keyboardHeight:kbHeight];
}
@end

// Retain the target for the lifetime of the app so the button actions fire.
static Zu4ButtonTarget *g_btn_target = nil;

// SDL's UIKit view controller posts SDL_WINDOWEVENT_RESIZED once the view's
// bounds have actually settled after a rotation (see viewDidLayoutSubviews in
// SDL_uikitviewcontroller.m) -- a more reliable signal than a UIKit device-
// orientation notification, and already exactly in sync with what the SDL
// renderer itself uses to re-letterbox the game view. We piggyback on it to
// keep the button overlay and the portrait keyboard-forcing behavior in sync.
// Event watches run synchronously on whatever thread posts the event (here,
// the main thread, from inside a UIKit layout pass), so defer the actual work
// like the keyboard notification handlers above do.
static int SDLCALL zu4_ios_window_event_watch(void *userdata, SDL_Event *event)
{
	if(event->type != SDL_WINDOWEVENT || event->window.event != SDL_WINDOWEVENT_RESIZED)
		return 0;
	if(g_window == NULL || event->window.windowID != SDL_GetWindowID(g_window))
		return 0;

	CGSize size = CGSizeMake(event->window.data1, event->window.data2);

	// Cross-check against the window's actual live size before trusting
	// this event -- it can occasionally report a size wildly unlike
	// anything on screen (e.g. with a screen-recording tool attached).
	if(g_root_view != nil && g_root_view.window != nil) {
		CGSize live = g_root_view.window.bounds.size;
		CGFloat maxLive = MAX(live.width, live.height);
		CGFloat maxEvt = MAX(size.width, size.height);
		if(maxLive > 1.0 && (maxEvt > maxLive * 1.5 || maxEvt < maxLive * 0.5))
			return 0;
	}

	BOOL portrait = event->window.data2 > event->window.data1;   // height > width
	dispatch_async(dispatch_get_main_queue(), ^{
		[g_btn_target handleRotation:portrait size:size];
	});
	return 0;
}

// SDL drives text input through a hidden UITextField whose accumulating text
// makes iOS show a predictive/candidate bar (and, on iOS 17+, inline
// predictions) — the "letters filling" the user sees. U4 is single-key driven,
// so we don't want any of that. Walk the view tree, find SDL's text field, and
// switch off every suggestion/prediction feature.
static void zu4_quiet_text_field(UIView *v)
{
	if(v == nil)
		return;
	if([v isKindOfClass:[UITextField class]]) {
		UITextField *tf = (UITextField *)v;
		tf.autocorrectionType = UITextAutocorrectionTypeNo;
		tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
		tf.spellCheckingType = UITextSpellCheckingTypeNo;
		tf.smartQuotesType = UITextSmartQuotesTypeNo;
		tf.smartDashesType = UITextSmartDashesTypeNo;
		tf.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
		// iOS 17+ inline predictions (ghosted suggestion text).
		if(@available(iOS 17.0, *))
			tf.inlinePredictionType = UITextInlinePredictionTypeNo;
	}
	for(UIView *sub in v.subviews)
		zu4_quiet_text_field(sub);
}

static void zu4_quiet_keyboard(void)
{
	// Defer so SDL has created/added its text field first.
	dispatch_async(dispatch_get_main_queue(), ^{
		for(UIWindow *w in [UIApplication sharedApplication].windows)
			zu4_quiet_text_field(w);
	});
}

void zu4_ios_show_keyboard(int show)
{
	if(show) {
		if(!SDL_IsTextInputActive())
			SDL_StartTextInput();
		zu4_quiet_text_field(g_root_view.window ?: g_root_view);
		zu4_quiet_keyboard();
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
	g_btn_target = [[Zu4ButtonTarget alloc] init];
	Zu4ButtonTarget *t = g_btn_target;

	[[NSNotificationCenter defaultCenter] addObserver:t
	    selector:@selector(keyboardWillShow:)
	    name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:t
	    selector:@selector(keyboardWillHide:)
	    name:UIKeyboardWillHideNotification object:nil];
	SDL_AddEventWatch(zu4_ios_window_event_watch, NULL);

	// Transparent, non-scaled button overlay on the window (not the SDL view).
	g_overlay = [[Zu4PassthroughView alloc] initWithFrame:uiwin.bounds];
	g_overlay.backgroundColor = [UIColor clearColor];
	g_overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[uiwin addSubview:g_overlay];

	g_portrait = root.bounds.size.height > root.bounds.size.width;
	[t applyLayoutForSize:root.bounds.size keyboardHeight:0];

	// Pre-warm SDL's text-input responder so the FIRST keyboard tap presents it
	// on a single press.
	dispatch_async(dispatch_get_main_queue(), ^{
		SDL_StartTextInput();
		SDL_StopTextInput();
		g_kb_shown = false;
		if(g_portrait)
			zu4_ios_show_keyboard(1);
	});
}
