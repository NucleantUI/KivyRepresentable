# KivyShaderNode

besides the nessary c api exposed to cython from swift, i guess the goal would be to get something
like what Angle (https://github.com/kivy-school/kivy2x/tree/upgrade/kivy/graphics/egl_backend) does for kivy..

but due to how kivy rendering works we only need one Shared VkImage
and kivy just does its normal rutine with drawing to the screen each frame (the shared VkImage)


https://github.com/kivy-school/kivy2x/blob/upgrade/kivy/core/window/_window_sdl2.pyx
https://github.com/kivy-school/kivy2x/blob/upgrade/kivy/core/window/window_sdl2.py

write new 
* _window_nui.pyx
* window_nui.py

that targets shared C api from KivyRepresentable

also many other sdl based we need to make _nui (nucleantui) versions for..

# KivyTexture Type
make compatible SDL Texture replacement, which i guess is just VkImage or whatever is lower level..


# CKivyWindow (just example what to call it)
write the C api for WindowProvider for kivy+cython
since kivy itself is ment to run as singleton
then there shouldnt be much issues with just requiring one shared ShaderNode

# SDL based draw instructions standin
* Circle - some standard shader for circle
* SmoothCircle - SmoothStep based Circle
* not sure about the rest

# new KivyWindowGroup
this should also replace the general usage of SDL also
and just forward mouse, touch, keyboard etc to kivy as nothing happened...


# Kivy Clock
NucleantApplication/Sources/NucleantSync
that calls shared c api, which cython exposes and does gil etc before calling the 
clock python callback..

# Replace Kivy self made clock, and feed it instance of DisplaySync callback instead..
the clock is very unstable in kivy and wont fit into our design since this doesnt need to keep app alive.
soo a DisplaySync callback should instead tick it...


# OpenGL (es3) shaders 
translate to SpirV when compiling shaders in kivy code..

# Providers
since alot of the providers like Text depends blit to textures
then we should just add our own Text provider which just uses Skia to draw onto 
texture and KivyShaderNode just draws result of that texture..
ignore sound / video and so on... 


# General Goal
* modify KivyRepresentable/kivy2x-upgrade as needed..
* as little impact on the kivy api itself, we are just trying to replace SDL and make kivy think its still just opengl and api wise nothing happened what kivy sees and does
* if possible just add new provider files and make setup.py be able to use environment settings as it does with everything else... we just dont need to build wheel as sdl anymore and wheel should just target shared libs from NucleantUI / KivyRepresentable..
* Python is launched on the side, and python doesnt launch this app, some logic in the KivyWindowGroup should just ensure python is launched else launch it first time... 


# Wasm support (later stage)
* setup to use pyodide python with it, which swift still launches or whatever.

