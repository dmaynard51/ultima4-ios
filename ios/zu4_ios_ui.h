/*
 *  zu4_ios_ui.h
 *  On-screen touch controls for the iOS port (native UIKit button overlay).
 */
#ifndef __zu4_ios_ui_h__
#define __zu4_ios_ui_h__

#include "SDL.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Add the on-screen control buttons (D-pad + action keys) on top of the SDL
 * view for the given window. Safe to call more than once; only installs once. */
void zu4_ios_setup_ui(SDL_Window *window);

/* Show/hide (or toggle) the iOS on-screen keyboard. */
void zu4_ios_show_keyboard(int show);
void zu4_ios_toggle_keyboard(void);

#ifdef __cplusplus
}
#endif

#endif /* __zu4_ios_ui_h__ */
