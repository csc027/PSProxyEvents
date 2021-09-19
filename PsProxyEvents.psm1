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

<#

.SYNOPSIS
Register a ScriptBlock to be executed alongside the supplied command.

.DESCRIPTION
This function saves a ScriptBlock to be executed, before or after, whenever the supplied command is executed.

.PARAMETER Command
The command that the events will attach to.

.PARAMETER CommandName
The name of the command that the events will attach to.  The Register-ProxyEvent command will throw an exception if the command cannot be found, or if there is more than one command with the name.

.PARAMETER ScriptBlock
The ScriptBlock that will be saved to be executed along with the supplied command.  The parameters passed to the ScriptBlock will be the same as the command that the ScriptBlock is attached to.

.PARAMETER Before
Determines whether the ScriptBlock will be saved to be executed before the supplied command.  Either the Before or After switch is required.

.PARAMETER After
Determines whether the ScriptBlock will be saved to be executed after the supplied command.  Either the Before or After switch is required.

.EXAMPLE
$Command = Get-Command -Module 'Microsoft.PowerShell.Management' -Name Get-ChildItem;
Register-ProxyEvent -Command $Command -ScriptBlock { Write-Host $Path } -Before -After;
Register-ProxyEvent -Command $Command -ScriptBlock { Write-Host $Path } -Before;
Register-ProxyEvent -Command $Command -ScriptBlock { Write-Host $Path } -Before -After;
Get-ChildItem -Path 'C:\';
C:\
C:\
C:\

        Directory: C:\


Mode                LastWriteTime         Length Name
----                -------------         ------ ----
d-r--         9/13/2021   9:53 PM                Program Files
d-r--          8/7/2021   9:49 PM                Program Files (x86)
d----         8/20/2020  11:53 AM                Temp
d-r--         8/20/2020   9:20 AM                Users
d----         9/17/2021   1:10 AM                Windows
C:\
C:\

.INPUTS
None

.OUTPUTS
None

#>

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
