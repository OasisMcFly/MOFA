#!/bin/zsh

# ============================================================
# Script Name: MOFA_Community_Microsoft_OneNote_Reset.zsh
# Repository: https://github.com/cocopuff2u/MOFA/tree/main/office_reset_tools/mofa_community_maintained
# Description: Resets the Microsoft OneNote
#
# Version History:
# 1.0.0 - Based on the latest available package from *Office-Reset.com*; recreated for MOFA to continue maintenance where *Office-Reset.com* left off.
#
# ============================================================


echo "Office-Reset: Starting postinstall for Reset_OneNote"
autoload is-at-least
APP_NAME="Microsoft OneNote"
APP_GENERATION="2019"
DOWNLOAD_2019="https://go.microsoft.com/fwlink/?linkid=820886"
DOWNLOAD_2016="https://go.microsoft.com/fwlink/?linkid=871755"
OS_VERSION=$(sw_vers -productVersion)

GetLoggedInUser() {
	LOGGEDIN=$(/bin/echo "show State:/Users/ConsoleUser" | /usr/sbin/scutil | /usr/bin/awk '/Name :/&&!/loginwindow/{print $3}')
	if [ "$LOGGEDIN" = "" ]; then
		echo "$USER"
	else
		echo "$LOGGEDIN"
	fi
}

SetHomeFolder() {
	HOME=$(dscl . read /Users/"$1" NFSHomeDirectory | cut -d ':' -f2 | cut -d ' ' -f2)
	if [ "$HOME" = "" ]; then
		if [ -d "/Users/$1" ]; then
			HOME="/Users/$1"
		else
			HOME=$(eval echo "~$1")
		fi
	fi
}

GetPrefValue() { # $1: domain, $2: key
     osascript -l JavaScript << EndOfScript
     ObjC.import('Foundation');
     ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('$1').objectForKey('$2'))
EndOfScript
}

GetCustomManifestVersion() {
	CHANNEL_NAME=$(GetPrefValue "com.microsoft.autoupdate2" "ChannelName")
	if [ "${CHANNEL_NAME}" = "Custom" ]; then
    	MANIFEST_SERVER=$(GetPrefValue "com.microsoft.autoupdate2" "ManifestServer")
    	echo "Office-Reset: Found custom ManifestServer ${MANIFEST_SERVER}"
    	FULL_UPDATER=$(/usr/bin/nscurl --location ${MANIFEST_SERVER}/0409ONMC2019.xml | grep -A1 -m1 'FullUpdaterLocation' | grep 'string' | sed -e 's,.*<string>\([^<]*\)</string>.*,\1,g')
    	echo "Office-Reset: Found custom FullUpdaterLocation ${FULL_UPDATER}"
    	if [[ "${FULL_UPDATER}" = "https://"* ]]; then
    		CUSTOM_VERSION=$(/usr/bin/nscurl --location ${MANIFEST_SERVER}/0409ONMC2019-chk.xml | grep -A1 -m1 'Update Version' | grep 'string' | sed -e 's,.*<string>\([^<]*\)</string>.*,\1,g')
    		echo "Office-Reset: Found custom update version ${CUSTOM_VERSION}"
    	fi
    fi
}

RepairApp() {
	if [[ "${APP_GENERATION}" == "2016" ]]; then
		DOWNLOAD_URL="${DOWNLOAD_2016}"
	else
		DOWNLOAD_URL="${DOWNLOAD_2019}"
	fi

	DOWNLOAD_FOLDER="/Users/Shared/OnDemandInstaller/"
	if [ -d "$DOWNLOAD_FOLDER" ]; then
		rm -rf "$DOWNLOAD_FOLDER"
	fi
	mkdir -p "$DOWNLOAD_FOLDER"

	GetCustomManifestVersion
	if [[ -z "${CUSTOM_VERSION}" ]]; then
		CDN_PKG_URL=$(/usr/bin/nscurl --location --head $DOWNLOAD_URL --dump-header - | awk '/Location/' | cut -d ' ' -f2 | tail -1 | awk '{$1=$1};1')
	else
		CDN_PKG_URL="${FULL_UPDATER}"
	fi
	
	echo "Office-Reset: Package to download is ${CDN_PKG_URL}"
	CDN_PKG_NAME=$(/usr/bin/basename "${CDN_PKG_URL}")

	CDN_PKG_SIZE=$(/usr/bin/nscurl --location --head $CDN_PKG_URL --dump-header - | awk '/Content-Length/' | cut -d ' ' -f2 | tail -1 | awk '{$1=$1};1')
	CDN_PKG_MB=$(/bin/expr ${CDN_PKG_SIZE} / 1000 / 1000)
	echo "Office-Reset: Download package is ${CDN_PKG_MB} megabytes in size"

	echo "Office-Reset: Starting ${APP_NAME} package download"
	/usr/bin/nscurl --background --download --large-download --location --download-directory $DOWNLOAD_FOLDER $CDN_PKG_URL
	echo "Office-Reset: Finished package download"

	LOCAL_PKG_SIZE=$(cd "${DOWNLOAD_FOLDER}" && stat -qf%z "${CDN_PKG_NAME}")
	if [[ "${LOCAL_PKG_SIZE}" == "${CDN_PKG_SIZE}" ]]; then
		echo "Office-Reset: Downloaded package is wholesome"
	else
		echo "Office-Reset: Downloaded package is malformed. Local file size: ${LOCAL_PKG_SIZE}"
		echo "Office-Reset: Please manually download and install ${APP_NAME} from ${CDN_PKG_URL}"
		exit 0
	fi

	LOCAL_PKG_SIGNING=$(/usr/sbin/pkgutil --check-signature ${DOWNLOAD_FOLDER}${CDN_PKG_NAME} | awk '/Developer ID Installer'/ | cut -d ':' -f 2 | awk '{$1=$1};1')
	if [[ "${LOCAL_PKG_SIGNING}" == "Microsoft Corporation (UBF8T346G9)" ]]; then
		echo "Office-Reset: Downloaded package is signed by Microsoft"
	else
		echo "Office-Reset: Downloaded package is not signed by Microsoft"
		echo "Office-Reset: Please manually download and install ${APP_NAME} from ${CDN_PKG_URL}"
		exit 0
	fi

	echo "Office-Reset: Starting package install"
	sudo /usr/sbin/installer -pkg ${DOWNLOAD_FOLDER}${CDN_PKG_NAME} -target /
	if [ $? -eq 0 ]; then
		echo "Office-Reset: Package installed successfully"
	else
		echo "Office-Reset: Package installation failed"
		echo "Office-Reset: Please manually download and install ${APP_NAME} from ${CDN_PKG_URL}"
		exit 0
	fi
	echo "Office-Reset: Exiting without removing configuration data"
	exit 0
}

## Main
LoggedInUser=$(GetLoggedInUser)
SetHomeFolder "$LoggedInUser"
echo "Office-Reset: Running as: $LoggedInUser; Home Folder: $HOME"

/usr/bin/pkill -9 'Microsoft OneNote'

if [ -d "/Applications/Microsoft OneNote.app" ]; then
	APP_VERSION=$(defaults read /Applications/Microsoft\ OneNote.app/Contents/Info.plist CFBundleVersion)
	echo "Office-Reset: Found version ${APP_VERSION} of ${APP_NAME}"
	if ! is-at-least 16.17 $APP_VERSION; then
		APP_GENERATION="2016"
	fi
	if [[ "${APP_GENERATION}" == "2019" ]]; then
		if ! is-at-least 16.73 $APP_VERSION && is-at-least 11.0.0 $OS_VERSION; then
			echo "Office-Reset: The installed version of ${APP_NAME} (2019 generation) is ancient. Updating it now"
			RepairApp
		fi
		GetCustomManifestVersion
		if [[ "${CUSTOM_VERSION}" ]] && [[ "${APP_VERSION}" != "${CUSTOM_VERSION}" ]]; then
			echo "Office-Reset: ${APP_NAME} is ${APP_VERSION} on-disk, but the pinned version has been set to ${CUSTOM_VERSION}. Removing and reinstalling"
			/bin/rm -rf /Applications/Microsoft\ OneNote.app
			RepairApp
		fi
	fi
	if [[ "${APP_GENERATION}" == "2016" ]]; then
		if ! is-at-least 16.16 $APP_VERSION; then
			echo "Office-Reset: The installed version of ${APP_NAME} (2016 generation) is ancient. Updating it now"
			RepairApp
		fi
	fi
	echo "Office-Reset: Checking the app bundle for corruption"
	/usr/bin/codesign -vv --deep /Applications/Microsoft\ OneNote.app
	if [ $? -gt 0 ]; then
		CODESIGN_ERROR=$(/usr/bin/codesign -vv --deep /Applications/Microsoft\ OneNote.app)
		echo "Office-Reset: The ${APP_NAME} app bundle is damaged and reporting error ${CODESIGN_ERROR}"
		if [[ "${CODESIGN_ERROR}" = *"OLE.framework"* ]]; then
			echo "Office-Reset: Only OLE.framework has been modified. Ignoring the repair"
		else
			echo "Office-Reset: The ${APP_NAME} app bundle is damaged and will be removed and reinstalled"
			/bin/rm -rf /Applications/Microsoft\ OneNote.app
			RepairApp
		fi
	else
		echo "Office-Reset: Codesign passed successfully"
	fi
else
	echo "Office-Reset: ${APP_NAME} was not found in the default location"
fi

echo "Office-Reset: Removing configuration data for ${APP_NAME}"
/bin/rm -f /Library/Preferences/com.microsoft.onenote.mac.plist
/bin/rm -f /Library/Managed Preferences/com.microsoft.onenote.mac.plist
/bin/rm -f $HOME/Library/Preferences/com.microsoft.onenote.mac.plist
## /bin/rm -rf $HOME/Library/Containers/com.microsoft.onenote.mac
## OneNote Sync Cache is under $HOME/Library/Containers/com.microsoft.onenote.mac/Data/Library/Application\ Support/Microsoft\ User\ Data/
/bin/rm -rf $HOME/Library/Containers/com.microsoft.onenote.mac.shareextension
/bin/rm -rf $HOME/Library/Application\ Scripts/com.microsoft.onenote.mac
/bin/rm -rf $HOME/Library/Application\ Scripts/com.microsoft.onenote.mac.shareextension

/bin/rm -rf /Applications/.Microsoft\ OneNote.app.installBackup

/bin/rm -rf $HOME/Library/Group\ Containers/UBF8T346G9.Office/OneNote
/bin/rm -rf $HOME/Library/Group\ Containers/UBF8T346G9.Office/FontCache
/bin/rm -rf $HOME/Library/Group\ Containers/UBF8T346G9.Office/TemporaryItems

exit 0
