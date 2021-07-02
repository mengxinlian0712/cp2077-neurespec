local Module = require('core/support/Module')
local Cron = require('core/services/Cron')
local GameLocale = require('core/services/GameLocale')
local PlayerDevData = require('game/systems/PlayerDevData')

---@class CharacterPerksMenu : Module
---@field upgradePerkAction CName
---@field revokePerkAction CName
---@field mainController PerksMainGameController
---@field revokeTooltipHint inkWidget
local CharacterPerksMenu = Module.extend()

---@protected
function CharacterPerksMenu:Initialize()
	self.upgradePerkAction = CName.new('upgrade_perk')
	self.revokePerkAction = CName.new('disassemble_item')
end

---@public
function CharacterPerksMenu:OnBootstrap()
	---@param this PerksMainGameController
	Observe('PerksMainGameController', 'OnInitialize', function(this)
		self.mainController = this
	end)

	Observe('PerksMainGameController', 'OnUninitialize', function()
		self.mainController = nil
		self.revokeTooltipHint = nil
	end)

	---@param perkData BasePerkDisplayData
  	Override('PerksMainGameController', 'SetPerksButtonHintHoverOver', function(_, perkData)
		if perkData then
			self:SetPerkButtonHints(perkData)
		end
	end)

	Observe('PerksMainGameController', 'SetPerksButtonHintHoverOut', function()
		self:ResetPerkButtonHints()
	end)

	---@param this PerkDisplayController
	---@param event inkPointerEvent
	Observe('PerkDisplayController', 'OnPerkDisplayHold', function(this, event)
		local playerData = PlayerDevData.resolve()
		local perkData = this.displayData

		if event:IsAction(self.revokePerkAction) and playerData:CanRevokePerk(perkData.level) then
			local progress = event:GetHoldProgress()

			if not this.holdStarted and progress >= 0 then
				this.holdStarted = true
			elseif this.holdStarted and progress >= 1 then
				if this.isTrait then
					playerData:RevokeTrait(perkData.type)
				else
					playerData:RevokePerk(perkData.type)
				end

				this.recentlyPurchased = true
				self:UpdateDisplayData(this)

				this:PlaySound('Item', 'OnCraftFailed')
				this:PlayLibraryAnimation('buy_perk')
			end
		end
	end)

	---@param this PerkDisplayController
	---@param perkData BasePerkDisplayData
	Observe('PerkDisplayController', 'Setup', function(this, perkData)
		if this.recentlyPurchased then
			if perkData then
				-- Nested RTTI call workaround
				Cron.NextTick(function()
					self:SetPerkButtonHints(this.dataManager.parentGameCtrl, perkData)
				end)
			end

			this.recentlyPurchased = false
		end
	end)
end

---@protected
---@param perkData BasePerkDisplayData
function CharacterPerksMenu:SetPerkButtonHints(perkData)
	if self.mainController then
		local playerData = PlayerDevData.resolve()

		if playerData:CanRevokePerk(perkData.level) then
			self.mainController.buttonHintsController:AddButtonHint(self.revokePerkAction, GameLocale.ActionHold('LocKey#17848'))
		else
			self.mainController.buttonHintsController:RemoveButtonHint(self.revokePerkAction)
		end

		if self.mainController.dataManager:IsPerkUpgradeable(perkData) then
			self.mainController.buttonHintsController:AddButtonHint(self.upgradePerkAction, GameLocale.ActionHold('UI-ScriptExports-Buy0'))
		else
			self.mainController.buttonHintsController:RemoveButtonHint(self.upgradePerkAction)
		end

		local cursorData = MenuCursorUserData.new()
		cursorData:AddAction(self.upgradePerkAction)
		cursorData:AddAction(self.revokePerkAction)
		cursorData:SetAnimationOverride('hoverOnHoldToComplete')

		self.mainController:SetCursorContext('Hover', cursorData)
	end
end

---@protected
function CharacterPerksMenu:ResetPerkButtonHints()
	if self.mainController then
		self.mainController.buttonHintsController:RemoveButtonHint(self.revokePerkAction)
	end
end

---@protected
---@param perkController PerkDisplayController
function CharacterPerksMenu:UpdateDisplayData(perkController)
	---@type PerksMainGameController
	local mainController = perkController.dataManager.parentGameCtrl
	local perkData = perkController.displayData

	if perkController.isTrait then
		mainController.perksScreenController:OnTraitBoughtEvent(
			TraitBoughtEvent.new({ traitType = perkData.type })
		)
	else
		mainController.perksScreenController:OnPerkBoughtEvent(
			PerkBoughtEvent.new({ perkType = perkData.type })
		)
	end

	perkController.dataManager:UpdateData()
end

return CharacterPerksMenu