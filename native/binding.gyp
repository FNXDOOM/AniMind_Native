{
  "targets": [
    {
      "target_name": "addon",
      "msvs_toolset": "v143",
      "sources": [ "src/addon.cc" ],
      "include_dirs": [
        "<!(node -p \"require('node-addon-api').include\")",
        "node_modules/node-addon-api",
        "include"
      ],
      "conditions": [
        [ 'OS=="win"', {
          "msvs_disabled_warnings": ["4996"],
          "msvs_settings": {
            "VCCLCompilerTool": {
              "ExceptionHandling": 1
            }
          },
          "link_settings": {
            "libraries": [
              "opengl32.lib",
              "gdi32.lib"
            ]
          }
        } ]
      ],
      "cflags!": [ "-fno-exceptions" ],
      "cflags_cc!": [ "-fno-exceptions" ],
      "defines": [ "NAPI_CPP_EXCEPTIONS" ]
    }
  ]
}
