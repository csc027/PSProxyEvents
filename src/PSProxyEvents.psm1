$script:EventBlocks = @{};
$script:ProxyModuleNamePrefix = '__DynamicModule_Proxy_';

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
	'Get-ExternalCommand' = {
		[CmdletBinding()]
		param (
			[Parameter(Position = 0, Mandatory = $true)]
			[String] $CommandName
		)

		end {
			return Microsoft.PowerShell.Core\Get-Command -Name $CommandName -All -ErrorAction 'SilentlyContinue' | Where-Object { $_.ModuleName -notlike $script:ProxyModuleNamePrefix + '*' };
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
Register-ProxyEvent -Command $Command -ScriptBlock { Write-Host $Path } -Before -After;
Register-ProxyEvent -Command $Command -ScriptBlock { Write-Host $Path } -Before;
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

.EXAMPLE
Register-ProxyEvent -CommandName 'Get-ChildItem' -ScriptBlock { Write-Host $Path } -Before -After;
Register-ProxyEvent -CommandName 'Get-ChildItem' -ScriptBlock { Write-Host $Path } -Before -After;
Register-ProxyEvent -CommandName 'Get-ChildItem' -ScriptBlock { Write-Host $Path } -Before;
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

.NOTES
To avoid infinite loops, make sure that any commands running inside the ScriptBlocks being saved are not ones that are being attached to.

#>

function Register-ProxyEvent {
	[CmdletBinding(DefaultParameterSetName = 'CommandBefore')]
	param (
		[Parameter(Position = 0, Mandatory = $true, ParameterSetName = 'CommandBefore')]
		[Parameter(Position = 0, Mandatory = $true, ParameterSetName = 'CommandAfter')]
		[Parameter(Position = 0, Mandatory = $true, ParameterSetName = 'CommandBeforeAfter')]
		[System.Management.Automation.CommandInfo] $Command,

		[Parameter(Position = 0, Mandatory = $true, ParameterSetName = 'CommandNameBefore')]
		[Parameter(Position = 0, Mandatory = $true, ParameterSetName = 'CommandNameAfter')]
		[Parameter(Position = 0, Mandatory = $true, ParameterSetName = 'CommandNameBeforeAfter')]
		[String] $CommandName,

		[Parameter(Position = 1, Mandatory = $true)]
		[ScriptBlock] $ScriptBlock,

		[Parameter(Mandatory = $true, ParameterSetName = 'CommandBefore')]
		[Parameter(Mandatory = $true, ParameterSetName = 'CommandNameBefore')]
		[Parameter(Mandatory = $true, ParameterSetName = 'CommandBeforeAfter')]
		[Parameter(Mandatory = $true, ParameterSetName = 'CommandNameBeforeAfter')]
		[Switch] $Before,

		[Parameter(Mandatory = $true, ParameterSetName = 'CommandAfter')]
		[Parameter(Mandatory = $true, ParameterSetName = 'CommandNameAfter')]
		[Parameter(Mandatory = $true, ParameterSetName = 'CommandBeforeAfter')]
		[Parameter(Mandatory = $true, ParameterSetName = 'CommandNameBeforeAfter')]
		[Switch] $After
	)

	begin {
		# Make sure that the user is not trying to register against a function from any dynamic modules created from this function
		if ($PSCmdlet.ParameterSetName -notlike 'CommandName*' -and $Command.ModuleName -like $script:ProxyModuleNamePrefix + '*') {
			throw New-Object -TypeName System.ArgumentException `
				-ArgumentList 'Registering against the aliases generated by this function will cause an infinite loop.  Please make sure that the supplied command is the one you expect.';
		}

		# Currently does not support attaching the ScriptBlock to multiple commands
		if ($PSCmdlet.ParameterSetName -like 'CommandName*' -and @(& $script:SafeCommands['Get-ExternalCommand'] -CommandName $CommandName).Count -gt 1) {
			throw New-Object -TypeName System.NotSupportedException `
				-ArgumentList 'The current implementation does not support registering against multiple commands simultaneously.  Make sure that there is only one command with the name you supplied.';
		}

		# Unable to find the command to attach to
		if ($PSCmdlet.ParameterSetName -like 'CommandName*' -and -not @(& $script:SafeCommands['Get-ExternalCommand'] -CommandName $CommandName)) {
			throw New-Object -TypeName System.Management.Automation.CommandNotFoundException `
				-ArgumentList "Unable to find the command with the name '$CommandName'.";
		}

		# Normalize on the command
		if ($PSCmdlet.ParameterSetName -like 'CommandName*') {
			$Command = & $script:SafeCommands['Get-ExternalCommand'] -CommandName $CommandName;
		}

		# Does not support native applications right now
		if ($Command.CommandType -eq [System.Management.Automation.CommandTypes]::Application) {
			throw New-Object -TypeName System.NotSupportedException `
				-ArgumentList 'The current implementation does not support registering against application commands.';
		}

		$AliasName = $Command.Name;
		$FunctionName = & $script:SafeCommands['Get-ProxyEventFunctionName'] -Command $Command;
		$CommandName = & $script:SafeCommands['Get-CommandName'] -Command $Command;
		$DynamicModuleName = $script:ProxyModuleNamePrefix + $AliasName;

		$CommandDefinition = & $script:SafeCommands['New-ProxyEventFunction'] -Command $Command;
		$ProxyScriptBlock = [ScriptBlock]::Create($CommandDefinition);
	}

	end {
		& $script:SafeCommands['Save-ScriptBlock'] -Command $Command -ScriptBlock $ScriptBlock -Before:$Before -After:$After;

		# Set up the dynamic module with deep copied script blocks
		$ModuleBlock = {
			param (
				[String] $FunctionName,
				[String] $AliasName,
				[ScriptBlock[]] $BeforeEventBlocks = @(),
				[ScriptBlock[]] $AfterEventBlocks = @(),
				[ScriptBlock] $ProxyScriptBlock
			)
			# Copy the saved script blocks
			$script:BeforeEventBlocks = $BeforeEventBlocks;
			$script:AfterEventBlocks = $AfterEventBlocks;

			# Load the duplicate script block into the dynamic module's scope
			. $ProxyScriptBlock;

			# Create the alias to hide the original function
			Microsoft.PowerShell.Utility\Set-Alias -Name $AliasName -Value $FunctionName;

			# Make sure that the proxy command and the alias are visible externally when the module is imported
			Microsoft.PowerShell.Core\Export-ModuleMember -Function $FunctionName -Alias $AliasName;
		}

		# Create a dynamic module
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
