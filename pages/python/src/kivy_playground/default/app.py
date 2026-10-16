import os

from kivy.app import App
from kivy.lang import Builder
from kivy.uix.boxlayout import BoxLayout


class IntroScreen(BoxLayout):
    def on_button_click(self):
        self.ids.subtitle_label.text = "Explore the power of Python + KVLang!"
        self.ids.action_btn.text = "Ready to Build!"


class PlaygroundApp(App):
    def build(self):
        return Builder.load_file(os.path.join(os.path.dirname(__file__), "app.kv"))


if __name__ == "__main__":
    PlaygroundApp().run()
