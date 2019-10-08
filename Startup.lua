NBUI = {}

NBUI.name = "Notebook2018"
-- NBUI.version = "4.13"
NBUI.settings = {
	NB1_Anchor 					= {a = CENTER, b = CENTER, x = 0, y = -20},
	NB1_BookColor 				= {1, 1, 1, 1},		-- Color the book's texture.
	NB1_TextColor				= {0, 0, 0, 0.7},	-- Notebook title, page title, and text.
	NB1_SelectionColor			= {1, 1, 1, 0.5},	-- R, G, B, A. Between 0 and 1.
	NB1_WarningColor   			= {1, 0.1, 0.1, 0.7},
	NB1_ShowTitle 				= true,
	NB1_Title 					= "Notebook",
	NB1_Locked 					= true,
	NB1_NewPageTitle 			= "",		-- Empty defaults to time and date.
	NB1_ShowDialog 				= true,
	NB1_ChatButton 				= true,
	NB1_ChatButton_Max_Offset 	= 0,		-- Offsets the button's position.
	NB1_ChatButton_Min_Offset 	= 0,		-- ..
	NB1Pages 					= {},
	NB1_LastPageSeen			= 1,
	NB1_AccountWide 			= false,	-- Pages saved for all characters. Overrides character pages!
	NB1_EditModeHover 			= false,	-- Enter Edit Mode on mouse hover on page.
	NB1_EditModeClick 			= true,		-- Enter Edit Mode on mouse click on page.
	NB1_LeaveEditModeOnFocus 	= true,		-- Leave Edit Mode on page lose focus (click outside.)
	NB1_LeaveEditModeOnExit 	= false,	-- Leave Edit Mode on mouse exit page area.
	NB1_DoubleClickSelectPage 	= false,	-- Selects whole page when double clicking, instead of a word.
	NB1_EmoteRead 				= true,		-- Emotes /read when Notebook is open.
	NB1_EmoteIdle				= true,		-- Emotes /idle after closing the Notebook.
	NB1_SelectLine				= true,		-- Select whole line with by tripleclicking it.
	NB1_FormattedMode			= false,	-- Whether to display formatted-text mode Label over Editbox.
	NB1_BookTexture				= "esoui/art/lorelibrary/lorelibrary_paperbook.dds", -- The texture to use as the book.
	NB1_OnTop					= true,		-- The book stays on top of other UI elements, to help with taking notes.
	NB1_ClickableLinks			= true,		-- Whether chat links are active in the book.
	-- NB1_MailToPage				= 1,		-- Copy mail item into a new page. 0 - Disabled, 1 - Keybind, 2 - Automatic.
	NB1_MailToPage				= true,		-- Copy mail item into a new page.
}

-- TODO This one has less space for text:
-- esoui/art/lorelibrary/lorelibrary_dwemerbook.dds
-- Maybe increase base size from 1024 for it? Or option to resize texture?
-- NBUI.NB1MainWindow_Cover:SetTextureCoords(0, 1, 0, 1)
NBUI.BookTextures = {
	"esoui/art/lorelibrary/lorelibrary_paperbook.dds",
	"esoui/art/lorelibrary/lorelibrary_rubbingbook.dds",
	"esoui/art/lorelibrary/lorelibrary_skinbook.dds",
}
NBUI.BookTexturesNames = {
	"Paper Book",
	"Rubbing Book",
	"Skin Book",
}

local mailKey = '^%s*' .. '```' -- Identifier substring for mail reading.

function NBUI.ProtectText(text)
	return text:gsub([[\]], [[%%92]])
end

function NBUI.UnprotectText(text)
	return text:gsub([[%%92]], [[\]])
end

function NBUI.NoTagsText(text)
	-- Remove color tags.
	return text:gsub('|c%w%w%w%w%w%w', ''):gsub('|r', '')
end

function NBUI.Initialize()
	-- Load saved variables.
	NBUI.dbCharacter = ZO_SavedVars:New("NBUISVDB", 1, nil, NBUI.settings)
	NBUI.db = NBUI.dbCharacter

	NBUI.dbAccount = ZO_SavedVars:NewAccountWide("NBUISVDBACCT", 1, nil, NBUI.settings)
	NBUI.dbAccount.NB1_AccountWide = true -- Always reflect account mode when using it, like in settings.
	-- Switch to account settings.
	if NBUI.db.NB1_AccountWide then
		NBUI.db = NBUI.dbAccount
	end

	NB1_IndexPool = ZO_ObjectPool:New(Create_NB1_IndexButton, Remove_NB1_IndexButton)

	CreateNB1()

	Populate_NB1_ScrollList()
end

function NBUI.OnAddOnLoaded(event, addonName)
  if addonName == NBUI.name then
	NBUI.Initialize()

	CreateNBUISettings()

	ZO_CreateStringId("SI_BINDING_NAME_NBUI_NB1TOGGLE", GetString(SI_NBUI_NB1KEYBIND_LABEL))

	-- Add keybind to copy mail item into a new page, or update existing page.
	table.insert(MAIL_INBOX.selectionKeybindStripDescriptor, {
		name = GetString(SI_NBUI_COPYMAIL_NAME),
		keybind = "UI_SHORTCUT_TERTIARY",

		callback = function()
			local id = MAIL_INBOX.mailId
			local mail = MAIL_INBOX:GetMailData(id)
			if not mail then return end

			local subject = mail.subject
			local body = ReadMail(id)

			-- Remove key from body.
			local keyIndex = string.find(body, mailKey)
			if keyIndex then
				body = body:sub(keyIndex + #mailKey - 4) -- Account for regex in string.
			end

			-- Find a matching existing page.
			local page = 0
			for i = 1, #NBUI.db.NB1Pages do
				local title = NBUI.db.NB1Pages[i].title
				if subject == title then
					page = i
				end
			end

			local action = 'Created'
			if page == 0 then
				-- Mimick creating a new page, but with optional contents.
				NBUI.NB1NewPage(nil, subject, body)
			else
				-- Update existing page.
				NBUI.db.NB1Pages[page].text = body
				NBUI.SelectPage(i)
				action = 'Updated'
			end

			-- MAIL_INBOX:Delete()
			PlaySound(SOUNDS.MAIL_ITEM_DELETED)

			local userName = mail.senderDisplayName
			local from = ''
			if pageApproved then
				from = ' from ' .. userName
			end

			d(string.format('|cFFFFFFNOTEBOOK:|r %s page "%s"%s.', action, subject, from))
		end,

		visible = function()
			if not MAIL_INBOX.mailId or not NBUI.db.NB1_MailToPage then return false end
			-- if not MAIL_INBOX.mailId or NBUI.db.NB1_MailToPage < 1 then return false end

			-- local numAttachments, attachedMoney, codAmount = GetMailAttachmentInfo(MAIL_INBOX.mailId)

			-- if numAttachments > 0 or attachedMoney > 0 or codAmount > 0 then return false end

			return true
		end
	})
  end
end
EVENT_MANAGER:RegisterForEvent(NBUI.name, EVENT_ADD_ON_LOADED, NBUI.OnAddOnLoaded)