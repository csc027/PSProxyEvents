$script:EventBlocks = @{};
$script:SafeCommands = @{
	'Get-CommandName' = {
		[CmdletBinding()]
		param (
			[Parameter(Position = 0, Mandatory = $true)]
			[System.Management.Automation.CommandInfo] $Command
		)

		end {
			if ($Command.ModuleName) {
				return $Command.ModuleName + '\' + $Command.Name;
			}
			return $Command.Name;
		}
	};
	'Get-ProxyEventFunctionName' = {
		param (
			[Parameter(Position = 0, Mandatory = $true)]
			[System.Management.Automation.CommandInfo] $Command
		)

		end {
			return 'Invoke-Proxy' + ($Command.Name -replace '-', '')
		}
	};
	'New-ProxyEventAlias' = {
		[CmdletBinding()]
		param (
			[Parameter(Position = 0, Mandatory = $true)]
			[System.Management.Automation.CommandInfo] $Command
		)

		end {
		}
	};
	'New-ProxyEventFunction' = {
		[CmdletBinding()]
		param (
			[Parameter(Position = 0, Mandatory = $true)]
			[System.Management.Automation.CommandInfo] $Command
		)

		end {
			$MetaData = Microsoft.PowerShell.Utility\New-Object System.Management.Automation.CommandMetaData($Command);
			$CmdletBindingAttribute = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($MetaData);
			$ParamBlock = "param($([System.Management.Automation.ProxyCommand]::GetParamBlock($MetaData)))";

			$BeforeExecuteStatement = "foreach(`$Block in `$script:BeforeEventBlocks) { & `$Block @PsBoundParameters; }";
			$AfterExecuteStatement = "foreach(`$Block in `$script:AfterEventBlocks) { & `$Block @PsBoundParameters; }";

			$BeginBlock = [System.Management.Automation.ProxyCommand]::GetBegin($MetaData) -replace '\$SteppablePipeline\.Begin', "$BeforeExecuteStatement; `$SteppablePipeline.Begin";
			$ProcessBlock = [System.Management.Automation.ProxyCommand]::GetProcess($MetaData);
			$EndBlock = [System.Management.Automation.ProxyCommand]::GetEnd($MetaData) -replace '\$SteppablePipeline\.End\(\)', "`$SteppablePipeline.End(); $AfterExecuteStatement; ";

			return @"
function $(& $script:SafeCommands['Get-ProxyEventFunctionName'] -Command $Command) {
	$CmdletBindingAttribute
	$ParamBlock

	$DynamicParamBlock

	begin { $BeginBlock }

	process { $ProcessBlock }

	end { $EndBlock }
}
"@;

		}
	};
	'Save-ScriptBlock' = {
		param (
			[Parameter(Position = 0, Mandatory = $true)]
			[System.Management.Automation.CommandInfo] $Command,

			[Parameter(Position = 1, Mandatory = $true)]
			[ScriptBlock] $ScriptBlock,

			[Switch] $Before,

			[Switch] $After
		)

		begin {
			$CommandName = & $script:SafeCommands['Get-CommandName'] -Command $Command;
		}

		end {
			if ($null -eq $script:EventBlocks.$CommandName) {
				$script:EventBlocks.$CommandName = @{
					'After' = @();
					'Before' = @();
				};
			}

			$MetaData = Microsoft.PowerShell.Utility\New-Object System.Management.Automation.CommandMetaData($Command);
			$ParamBlock = "param($([System.Management.Automation.ProxyCommand]::GetParamBlock($MetaData)))";
			$ParamEventBlock = [ScriptBlock]::Create($ParamBlock + $ScriptBlock.ToString());

			if ($Before) {
				$script:EventBlocks.$CommandName.Before += @($ParamEventBlock);
			}

			if ($After) {
				$script:EventBlocks.$CommandName.After += @($ParamEventBlock);
			}
		}
	};
};

function Register-ProxyEvent {
	[CmdletBinding()]
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[System.Management.Automation.CommandInfo] $Command,

		[Parameter(Position = 1, Mandatory = $true)]
		[ScriptBlock] $ScriptBlock,

		[Switch] $Before,

		[Switch] $After
	)

	begin {
		$AliasName = $Command.Name;
		$FunctionName = & $script:SafeCommands['Get-ProxyEventFunctionName'] -Command $Command;
		$CommandName = & $script:SafeCommands['Get-CommandName'] -Command $Command;
		$DynamicModuleName = "__DynamicModule_Proxy_$AliasName";

		$CommandDefinition = & $script:SafeCommands['New-ProxyEventFunction'] -Command $Command;
		$ProxyScriptBlock = [ScriptBlock]::Create($CommandDefinition);
	}

	end {
		& $script:SafeCommands['Save-ScriptBlock'] @PsBoundParameters;

		$ModuleBlock = {
			param (
				[String] $FunctionName,
				[String] $AliasName,
				[ScriptBlock[]] $BeforeEventBlocks = @(),
				[ScriptBlock[]] $AfterEventBlocks = @(),
				[ScriptBlock] $ProxyScriptBlock
			)
			$script:BeforeEventBlocks = $BeforeEventBlocks;
			$script:AfterEventBlocks = $AfterEventBlocks;
			. $ProxyScriptBlock;
			Microsoft.PowerShell.Utility\Set-Alias -Name $AliasName -Value $FunctionName;
			Microsoft.PowerShell.Core\Export-ModuleMember -Function $FunctionName -Alias $AliasName;
		}

		$Module = Microsoft.PowerShell.Core\New-Module -Name $DynamicModuleName -ScriptBlock $ModuleBlock -ArgumentList @(
			$FunctionName,
			$AliasName,
			$script:EventBlocks.$CommandName.Before,
			$script:EventBlocks.$CommandName.After,
			$ProxyScriptBlock
		);

		if (Microsoft.PowerShell.Core\Get-Module -Name $DynamicModuleName) {
			Microsoft.PowerShell.Core\Remove-Module -Name $DynamicModuleName;
		}
		Microsoft.PowerShell.Core\Import-Module -ModuleInfo $Module -Global;
	}
}
