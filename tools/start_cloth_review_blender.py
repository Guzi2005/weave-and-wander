import addon_utils
import bpy

addon_utils.enable('blender_mcp', default_set=False, persistent=False)
if not getattr(bpy.context.scene, 'blendermcp_server_running', False):
    bpy.ops.blendermcp.start_server()
print('W&W cloth review MCP ready; existing files not modified')
