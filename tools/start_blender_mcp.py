"""Start the installed local bridge without changing the user's scene."""
import bpy
import addon_utils

addon_utils.enable("blender_mcp", default_set=True, persistent=True)
bpy.context.preferences.addons["blender_mcp"].preferences.telemetry_consent = False
bpy.ops.blendermcp.start_server()
