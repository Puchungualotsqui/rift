#+build js

package rift_client

import k2 "../karl2d"

LoadPixelMarks :: proc() -> (k2.Texture, bool) {
	return k2.load_texture_from_bytes(#load("assets/rift_marks.png"))
}

