local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local LuaSettings = require("frontend/luasettings")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")
local API = require("api")

local Plugin = WidgetContainer:new{
    name = "zeitdownload",
    is_doc_only = false
}

function Plugin:init()
    print("Loading Zeit plugin ==========================================")
    self.ui.menu:registerToMainMenu(self)
    print("Main menu registered")
    self.settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), "zeit_settings.lua"))
    print("settings opened")
end

function Plugin:setAccount()
    local username = self.settings:readSetting("username", "")
    local password = self.settings:readSetting("password", "")
    self.account_dialog = MultiInputDialog:new{
        title = _("Edit User Info"),
        fields = {
            {
                description = _('Username'),
                text = username,
                hint = _("E-Mail"),
            },
            {
                description = _('Password'),
                text = password,
                hint = _("Password"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        self.account_dialog:onClose()
                        UIManager:close(self.account_dialog)
                    end
                },
                {
                    text = _("Update"),
                    callback = function()
                        local fields = self.account_dialog:getFields()

                        if fields[1] == nil or fields[1] == "" or
                            fields[2] == nil or fields[2] == "" then
                            UIManager:show(InfoMessage:new{
                                text = _("Username and password can not be empty"),
                                timeout = 3,
                                icon = "notice-warning"
                            })
                            return
                        end

                        self.settings:saveSetting("username", fields[1])
                        self.settings:saveSetting("password", fields[2])
                        self.settings:flush()
                        self.account_dialog:onClose()
                        UIManager:close(self.account_dialog)
                    end
                },
            },
        },
    }
    UIManager:show(self.account_dialog)
    self.account_dialog:onShowKeyboard()
end

function Plugin:setDirectory()
    require("ui/downloadmgr"):new{
        onConfirm = function(path)
            self.settings:saveSetting("directory", path)
            self.settings:flush()
        end,
    }:chooseDir()
end

function Plugin:download()
    local dir = self.settings:readSetting("directory")
    if dir == nil then
        UIManager:show(InfoMessage:new {
            text = _("Set a target directory first"),
            timeout = 5,
            icon = "notice-warning"
        })
    else
        local path = API.Download(dir,
                 self.settings:readSetting("username", ""),
                 self.settings:readSetting("password", ""),
                 self.onError)
        UIManager:show(InfoMessage:new {
            text = "Starting download",
            timeout = 1,
            icon = "notice-info"
        })

        if path == nil then return end
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(path)
    end
end

function Plugin.onError(msg)
    print("ZEIT ERROR: " .. msg)
    UIManager:show(InfoMessage:new {
        text = msg,
        timeout = 5,
        icon = "notice-warning"
    })
end

function Plugin:addToMainMenu(menu_items)
    menu_items.zeit = {
        text = _("Die Zeit"),
        sorting_hint = "search",
        sub_item_table = {
            {
                text = _("Download"),
                callback = function() self:download() end,
            },
            {
                text = _("Configure Account"),
                callback = function() self:setAccount() end,
            },
            {
                text = _("Set directory"),
                callback = function() self:setDirectory() end,
            }
        }
    }
end

return Plugin
