VersionCheck = {
    gistUrl = "https://gist.githubusercontent.com/PiotreeQ/7821b3d71f4babe37e57b46af1d4faa5/raw/d1f4a7d8e9929273648fab2e5cca3909a35362fb/gistfile1.txt",
    currentVersion = GetResourceMetadata(GetCurrentResourceName(), "version", 0),
}

function VersionCheck.parseVersion(versionString)
    if not versionString then
        return nil
    end
    versionString = versionString:gsub("^v", "")
    local major, minor, patch = versionString:match("(%d+)%.(%d+)%.(%d+)")
    if not major then
        return nil
    end
    return {
        major = tonumber(major),
        minor = tonumber(minor),
        patch = tonumber(patch),
        original = versionString,
    }
end

function VersionCheck.isNewerVersion(currentVersion, remoteVersion)
    if not currentVersion or not remoteVersion then
        return false
    end
    if remoteVersion.major > currentVersion.major then
        return true
    end
    if remoteVersion.major < currentVersion.major then
        return false
    end
    if remoteVersion.minor > currentVersion.minor then
        return true
    end
    if remoteVersion.minor < currentVersion.minor then
        return false
    end
    return remoteVersion.patch > currentVersion.patch
end

function VersionCheck.run()
    print("^3[Version Check]^7 Checking for updates...")
    print("^3[Version Check]^7 Current version: ^5" .. (VersionCheck.currentVersion or "Unknown") .. "^7")
    PerformHttpRequest(VersionCheck.gistUrl, function(statusCode, responseBody)
        if statusCode == 200 then
            local success, versionData = pcall(json.decode, responseBody)
            if success and versionData and versionData.version then
                local currentVersion = VersionCheck.parseVersion(VersionCheck.currentVersion)
                local remoteVersion = VersionCheck.parseVersion(versionData.version)
                if not currentVersion then
                    print("^1[Version Check]^7 Error: Could not parse current version")
                    return
                end
                if not remoteVersion then
                    print("^1[Version Check]^7 Error: Could not parse remote version")
                    return
                end
                if VersionCheck.isNewerVersion(currentVersion, remoteVersion) then
                    print("^2[Version Check]^7 ========================================")
                    print("^2[Version Check]^7 UPDATE AVAILABLE!")
                    print("^2[Version Check]^7 Current Version: ^5v" .. currentVersion.original .. "^7")
                    print("^2[Version Check]^7 Latest Version:  ^2v" .. remoteVersion.original .. "^7")
                    print("^2[Version Check]^7 ========================================")
                    if versionData.changelog then
                        print("^2[Version Check]^7 Changelog:")
                        for _, change in ipairs(versionData.changelog) do
                            print("^2[Version Check]^7   • " .. change)
                        end
                        print("^2[Version Check]^7 ========================================")
                    end
                    if versionData.download_url then
                        print("^2[Version Check]^7 Download: ^3" .. versionData.download_url .. "^7")
                    end
                    if versionData.notes then
                        print("^2[Version Check]^7 " .. versionData.notes)
                    end
                    print("^2[Version Check]^7 ========================================")
                else
                    print("^2[Version Check]^7 You are running the latest version!")
                end
            else
                print("^1[Version Check]^7 Error: Invalid JSON response")
            end
        elseif statusCode == 404 then
            print("^1[Version Check]^7 Error: Version file not found (404)")
            print("^1[Version Check]^7 Check your Gist URL!")
        else
            print("^1[Version Check]^7 Error: HTTP " .. statusCode)
        end
    end, "GET", "", {})
end

CreateThread(function()
    Wait(5000)
    VersionCheck.run()
end)
