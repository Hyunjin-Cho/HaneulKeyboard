"""2026-10-10: Finder 설치 화면. 좌표는 배경 렌더러와 layout.json 하나를 공유한다."""
import json
import os

with open(defines["layout"], encoding="utf-8") as source:
    layout = json.load(source)
application = os.path.abspath(defines["app"])
appname = os.path.basename(application)
format = "UDZO"
compression_level = 9
files = [application]
hide_extensions = [appname]
symlinks = {"Applications": "/Applications"}
background = os.path.abspath(defines["background"])
icon = os.path.abspath(defines["icon"])
window_rect = ((200, 120), tuple(layout["windowSize"]))
default_view = "icon-view"
icon_size = layout["iconSize"]
text_size = layout["textSize"]
label_pos = "bottom"
arrange_by = None
icon_locations = {appname: tuple(layout["appCenter"]), "Applications": tuple(layout["applicationsCenter"])}
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
