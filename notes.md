Notes
=====

Things to look at:
  * SIGWINCH, signal sent on window size change.

Things to fix:
  * Extend snake buffer to allow for sizes greater than 16
  * Show score
  * Add walls
  * Spawn snake in random position/shape/direction
  * Keep stack of key input to allow for quick maneuvers
  * Detect terminal dimensions, spawn food all over
  * Game over screen/better resetting
  * Calculating time delta, currently inefficient (don't call clock_gettime twice)
  * Catch errors to function calls (getch, etc.)
