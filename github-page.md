# write KivyRepresentable Playground App for wasm for github pages

ok like in PyShader where it combines Monaco editor on left side and previewer on right side..

not sure if we need to write a custom/modifed version of current KivyWindowGroup
but it should be able to reload the kivy app when code changes in monaco
without having to restart the nucleant app part.. 
i guess for now its ok if kivy app inside just reload or whatever..

# write simple docs with playground window for showing the live preview
i guess using mkdocs / material 
dont make a big deal of the docs it self most important is there is tab for the playground


------------------------
            |
 kv code    |
            |
            |
-------------   kivy window
            |
            |
 py code    |
            |
------------------------


just label them as app.py app.kv

and build returns Builder.load_file(path to kv using __file__ to get current location of file dump) 
for now 




https://github.com/Py-Swift/PySwiftKitDemoPlugin

in case you need to see what we do here which also has the monaco stuff

the benefit is it has what swift side needs to interface with it 
and our nucleantapp package just needs to be able to preview/reload the kivy code
soo blending monaco api into can maybe make things easier in terms of reloading etc