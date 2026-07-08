/*
 * video.c
 * Copyright (C) 2020 R. Danbrook
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 */

/*
 * Rendering uses SDL2's built-in 2D renderer instead of raw OpenGL: the
 * 320x200 RGBA framebuffer is uploaded to a streaming texture each frame and
 * scaled to the window with nearest-neighbour filtering. SDL_Renderer picks the
 * best backend per platform (Metal on iOS/macOS, GL/D3D elsewhere), so this
 * builds and runs everywhere SDL2 does — including iOS — with no GL headers.
 */

#include <SDL.h>

#include "error.h"
#include "image.h"
#include "settings.h"
#include "u4_sdl.h"

#ifdef ZU4_IOS
#include "zu4_ios_ui.h"
#endif

static SDL_Window *window = NULL;
static SDL_Renderer *renderer = NULL;
static SDL_Texture *texture = NULL;

void zu4_ogl_swap() {
	Image *screen = zu4_img_get_screen();
	if (!renderer || !texture || !screen) { return; }

	SDL_UpdateTexture(texture, NULL, screen->pixels, SCREEN_WIDTH * 4);
	SDL_RenderClear(renderer);
	SDL_RenderCopy(renderer, texture, NULL, NULL);
	SDL_RenderPresent(renderer);
}

void zu4_video_init() {
	if (u4_SDL_InitSubSystem(SDL_INIT_VIDEO) < 0) {
		zu4_error(ZU4_LOG_ERR, "Unable to init SDL: %s", SDL_GetError());
	}

	atexit(SDL_Quit);

	SDL_ShowCursor(SDL_DISABLE);
	SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0"); /* nearest-neighbour */

	window = SDL_CreateWindow("Ultima IV",
		SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
		SCREEN_WIDTH * settings.scale, SCREEN_HEIGHT * settings.scale,
		SDL_WINDOW_SHOWN);

	renderer = SDL_CreateRenderer(window, -1,
		SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
	if (!renderer) {
		/* Fall back to a software renderer rather than failing outright. */
		renderer = SDL_CreateRenderer(window, -1, 0);
	}

	/* Draw at the native 320x200 resolution; the renderer scales to the window
	 * (and letterboxes on mismatched aspect ratios, e.g. a phone screen). */
	SDL_RenderSetLogicalSize(renderer, SCREEN_WIDTH, SCREEN_HEIGHT);

	texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA32,
		SDL_TEXTUREACCESS_STREAMING, SCREEN_WIDTH, SCREEN_HEIGHT);

#ifdef ZU4_IOS
	zu4_ios_setup_ui(window);
#endif
}

void zu4_video_deinit() {
	if (texture) { SDL_DestroyTexture(texture); texture = NULL; }
	if (renderer) { SDL_DestroyRenderer(renderer); renderer = NULL; }
	if (window) { SDL_DestroyWindow(window); window = NULL; }
	u4_SDL_QuitSubSystem(SDL_INIT_VIDEO);
}
