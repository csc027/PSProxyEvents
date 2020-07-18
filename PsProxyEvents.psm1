$script:InjectBlocks = @{};

function Get-CommandName {
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
}

function Get-ProxyEventFunctionName {
	param (
		[Parameter(Position = 0, Mandatory = $true)]
			[System.Management.Automation.CommandInfo] $Command
	)

	end {
		return 'Invoke-Proxy' + ($Command.Name -replace '-', '')
	}
}

function New-BackupAliasName {
	param (
		[String] $Name
	)

	begin {
		$i = 1
		while (Test-Path -Path "Alias\$Name.$i") {
			$i++;
		}
	}

	end {
		return "$Name.$i";
	}
}

function Save-ScriptBlock {
	[CmdletBinding()]
	param (
		[Parameter(Position = 0, Mandatory = $true)]
			[System.Management.Automation.CommandInfo] $Command,

		[Parameter(Position = 1, Mandatory = $true)]
			[ScriptBlock] $ScriptBlock,

		[Switch] $After,

		[Switch] $Before,

		[Switch] $Process
	)
	begin {
		$CommandName = if ($Command.ModuleName) {
			"$($Command.ModuleName)\$($Command.Name)";
		} else {
			$Command.Name;
		}
	}

	end {
		if ($null -eq $script:InjectBlocks.$CommandName) {
			$script:InjectBlocks.$CommandName = @{
				'After' = @();
				'Before' = @();
				'Process' = @();
			};
		}

		$ParamBlock = "param($([System.Management.Automation.ProxyCommand]::GetParamBlock($MetaData)))";
		$ParamInjectedBlock = [ScriptBlock]::Create($ParamBlock + $ScriptBlock.ToString());

		if ($After) {
			$script:InjectBlocks.$CommandName['After'] += $ParamInjectedBlock;
		}
		if ($Before) {
			$script:InjectBlocks.$CommandName['Before'] += $ParamInjectedBlock;
		}
		if ($Process) {
			$script:InjectBlocks.$CommandName['Process'] += $ParamInjectedBlock;
		}
	}
}

function Register-ProxyEvent {
	[CmdletBinding()]
	param (
		[Parameter(Position = 0, Mandatory = $true)]
			[System.Management.Automation.CommandInfo] $Command,

		[Parameter(Position = 1, Mandatory = $true)]
			[ScriptBlock] $ScriptBlock,

		[Switch] $After,

		[Switch] $Before,

		[Switch] $Process
	)

	begin {
		$FullCommandName = if ($Command.ModuleName) {
			"$($Command.ModuleName)\$($Command.Name)";
		} else {
			$Command.Name;
		}
		Save-ScriptBlock @PsBoundParameters;
		$MetaData = New-Object System.Management.Automation.CommandMetaData($Command);
		$CmdletBindingAttribute = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($MetaData);
		$ParamBlock = "param($([System.Management.Automation.ProxyCommand]::GetParamBlock($MetaData)))";
		$ArgsStatement = if ($Command.Definition -match "\`$args") {
			'$PSBoundParameters.Add(''$args'', $args);';
		}
		$OutBufferStatement = if ($Command.Parameters.ContainsKey('OutBuffer')) {
			'$OutBuffer = $null; if ($PSBoundParameters.TryGetValue(''OutBuffer'', [ref]$OutBuffer)) { $PSBoundParameters[''OutBuffer''] = 1; }';
		}
		$DynamicParamBlock = if (($Command.Parameters.Values | Microsoft.Powershell.Core\Where-Object { $_.IsDynamic }).Count -gt 0) {
			"dynamicparam { $([System.Management.Automation.ProxyCommand]::GetDynamicParam($MetaData)) }";
		}

		$CommandDefinition = @"
function global:Invoke-Proxy$($Command.Name -replace '-', '') {
	$CmdletBindingAttribute
	$ParamBlock

	$DynamicParamBlock

	begin {
		try {
			$OutBufferStatement
			`$WrappedCmd = `$ExecutionContext.InvokeCommand.GetCommand('$FullCommandName', [System.Management.Automation.CommandTypes]::$($Command.CommandType));
			$ArgsStatement
			`$ScriptCmd = { & `$WrappedCmd @PSBoundParameters };

			foreach(`$Block in `$script:InjectBlocks.'$FullCommandName'.Before) {
				& `$Block @PsBoundParameters;
			}

			`$SteppablePipeline = `$ScriptCmd.GetSteppablePipeline(`$MyInvocation.CommandOrigin);
			`$SteppablePipeline.Begin(`$PSCmdlet);
		} catch {
			throw;
		}
	}

	process {
		try {
			`$SteppablePipeline.Process(`$_);
		} catch {
			throw;
		}
	}

	end {
		try {
			`$SteppablePipeline.End();

			foreach(`$Block in `$script:InjectBlocks.'$FullCommandName'.After) {
				& `$Block @PsBoundParameters;
			}
		} catch {
			throw;
		}
	}
}
<#

.ForwardHelpTargetName $FullCommandName
.ForwardHelpCategory $($Command.CommandType)

#>
"@;

	}

	end {
		Invoke-Expression -Command $CommandDefinition;
	}
}
