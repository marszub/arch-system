hl.on("hyprland.start", function()
    hl.exec_cmd("regreet --config /etc/greetd/regreet.toml; hyprctl dispatch 'hl.dsp.exit()'")
end)

hl.config({
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        disable_hyprland_guiutils_check = true,
    },
})
