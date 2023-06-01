require('socket')
local https = require('ssl.https')
local ltn12 = require('ltn12')

local API = {}
function Urlencode(s)
    return s:gsub("([^%w%-%.%_%~])",function(c)return("%%%02X"):format(c:byte())end)
end

function Join(it, sep)
    local result = ''

    for i, value in ipairs(it) do
        if i == 1 then
            result = value
        else
        result = result .. sep .. value

        end
    end

    return result
end

-- RFC 6265 – HTTP State Management Mechanism
-- This does not match all possible cookie headers, it is a crude approximation
function SetCookies(cookie_jar, header)
    if header == nil then
        return 
    end
    local cookie_regex = "(%g-)=(.-)[;,]"
    print(header)

    for k,v in string.gmatch(header, cookie_regex) do
        local r = string.lower(k)
        if r == "domain" or r == "path" or r == "expires" or r == "samesite" then
        else
            cookie_jar[k] = v
            print("Setting cookie " .. k)
        end
    end
end

function GetCookieHeader(cookie_jar)
    local header = ""
    for k, v in pairs(cookie_jar) do
        if header ~= "" then
            header = header .. "; "
        end
        header = header .. string.format("%s=%s", k, v)
    end

    return header
end

function API.Download(target_folder, username, password, error_callback)
    if target_folder == nil or error_callback == nil then
        return nil
    end

    print("Downloading")
    local cookie_jar = {}
    local b, c, h, s = https.request('https://meine.zeit.de/anmelden')
    if c ~= 200 then
        error_callback("Could not request login site")
        return nil
    end
    SetCookies(cookie_jar, h['set-cookie'])
    local csrf_token = cookie_jar['csrf_token']

    -- Logging in
    local body = "email=" .. Urlencode(username)
             .. "&pass=" .. Urlencode(password)
             .. "&csrf_token=" .. csrf_token

    b, c, h, s = https.request {
        url = 'https://meine.zeit.de/anmelden',
        method = 'POST',
        headers = {
            ['Cookie'] = GetCookieHeader(cookie_jar),
            ['Origin'] = 'https://meine.zeit.de'
        },
        source = ltn12.source.string(body)
    }
    SetCookies(cookie_jar, h['set-cookie'])

    if c ~= 302 then
        error_callback("Could not login, password correct?")
        return nil
    end

    cookie_jar['csrf_token'] = nil

    b, c, h, s = https.request {
        url = 'https://epaper.zeit.de/abo/diezeit',
        headers = {
            ['Origin'] = 'https://meine.zeit.de',
            ['Cookie'] = GetCookieHeader(cookie_jar),
        }
    }

    local html_source = {}
    if c == 302 then
        -- try again with new cookies
        SetCookies(cookie_jar, h['set-cookie'])
        b, c, h, s = https.request {
            url = 'https://epaper.zeit.de/abo/diezeit',
            headers = {
                ['Origin'] = 'https://meine.zeit.de',
                ['Cookie'] = GetCookieHeader(cookie_jar),
            },
            sink = ltn12.sink.table(html_source),
        }
    end

    if c ~= 200 then
        error_callback("Could not find newest paper")
        return nil
    end


    local html_source_string = table.concat(html_source)
    local href = string.match(html_source_string, '\n%s+<a href="([^"]-)"[^>]*>ZUR AKTUELLEN AUSGABE')


    local req_url = 'https://epaper.zeit.de' .. href
    print(req_url)
    b, c, h, s = https.request {
        url = req_url,
        headers = {
            ['Origin'] = 'https://meine.zeit.de',
            ['Cookie'] = GetCookieHeader(cookie_jar),
        },
        sink = ltn12.sink.table(html_source),
    }

    if c ~= 200 then
        error_callback("Failed loading html with epub download link", c)
        return nil
    end
    html_source_string = table.concat(html_source)

    if string.find(html_source_string, "EPUB FOLGT IN KÜRZE") ~= nil then
        error_callback("epub not available yet")
        return nil
    end

    local epub_href = string.match(html_source_string, '<a[^>]*href="([^"]+)"[^>]*>%s+EPUB FÜR E%-READER LADEN')

    if epub_href == nil then
        print(html_source_string)
        error_callback("Could not extract epub link")
        return nil
    end

    local tmp_file_path = os.tmpname()
    local tmp_file = io.open(tmp_file_path, "wb")
    if tmp_file == nil then
        error_callback("Could not open temp file")
        return nil
    end
    print("Requesting epub from " .. epub_href)
    b, c, h, s = https.request {
        url = epub_href,
        headers = {
            ['Origin'] = 'https://meine.zeit.de',
            ['Cookie'] = GetCookieHeader(cookie_jar),
        },
        sink = ltn12.sink.file(tmp_file)
    }

    if c ~= 200 then
        error_callback("Could not download epub, error code " .. c)
        return nil
    end
    local filename = string.match(h['content-disposition'], 'filename=(%S+)')
    local target_path = target_folder .. '/' .. filename
    os.rename(tmp_file_path, target_path)

    return target_path
end


return API
