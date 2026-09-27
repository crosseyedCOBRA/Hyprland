#!/usr/bin/env sh
# Used by quickshell's workspace pills to switch Awesome tags by clicking.
# Usage: view-tag.sh <output-name> <tag-name>
awesome-client <<LUA
for scr in screen do
  if scr.outputs["$1"] then
    for _, t in ipairs(scr.tags) do
      if t.name == "$2" then t:view_only() end
    end
  end
end
LUA
