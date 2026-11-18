package server

import "core:c"

when ODIN_OS == .Windows {
	foreign import ws_pthread "deps/libwinpthread.lib"
	foreign import ws_compat "deps/libwscompat.lib"

	foreign ws_pthread {
		pthread_mutex_lock :: proc(mutex: rawptr) -> c.int ---
		pthread_mutex_unlock :: proc(mutex: rawptr) -> c.int ---
		pthread_mutex_init :: proc(mutex, attributes: rawptr) -> c.int ---
		pthread_mutex_destroy :: proc(mutex: rawptr) -> c.int ---
		pthread_cond_init :: proc(condition, attributes: rawptr) -> c.int ---
		pthread_cond_destroy :: proc(condition: rawptr) -> c.int ---
		pthread_cond_timedwait64 :: proc(condition, mutex, time: rawptr) -> c.int ---
		pthread_cond_signal :: proc(condition: rawptr) -> c.int ---
		pthread_create :: proc(thread, attributes, start, argument: rawptr) -> c.int ---
		pthread_detach :: proc(thread: rawptr) -> c.int ---
		pthread_join :: proc(thread, result: rawptr) -> c.int ---
		clock_gettime64 :: proc(clock: c.int, time: rawptr) -> c.int ---
	}

	foreign ws_compat {
		@(link_name = "wsserver_compat_link")
		WsServerCompatLink :: proc(mutexLock, mutexUnlock, mutexInit, mutexDestroy, conditionInit, conditionDestroy, conditionTimedWait, conditionSignal, threadCreate, threadDetach, threadJoin, clockGettime: rawptr) ---
	}
}
