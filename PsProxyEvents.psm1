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

		[Switch] $Before,

		[Switch] $After
	)
	begin {
		$CommandName = Get-CommandName -Command $Command;
	}

	end {
		if ($null -eq $script:InjectBlocks.$CommandName) {
			$script:InjectBlocks.$CommandName = @{
				'After' = @();
				'Before' = @();
			};
		}

		$MetaData = Microsoft.PowerShell.Utility\New-Object System.Management.Automation.CommandMetaData($Command);
		$ParamBlock = "param($([System.Management.Automation.ProxyCommand]::GetParamBlock($MetaData)))";
		$ParamInjectedBlock = [ScriptBlock]::Create($ParamBlock + $ScriptBlock.ToString());

		if ($After) {
			$script:InjectBlocks.$CommandName['After'] += $ParamInjectedBlock;
		}
		if ($Before) {
			$script:InjectBlocks.$CommandName['Before'] += $ParamInjectedBlock;
		}
	}
}

function New-ProxyEventAlias {
	[CmdletBinding()]
	param (
		[Parameter(Position = 0, Mandatory = $true)]
			[System.Management.Automation.CommandInfo] $Command
	)

	begin {
		if (
			-not (Get-Command -Name $Command.Name -CommandType 'Alias' -Module 'PsProxyEvents' -ErrorAction 'Ignore') `
			-and (Get-Command -Name $Command.Name -CommandType 'Alias' -ErrorAction 'Ignore')
		) {
			# Backup old alias
			Rename-Item -Path "Alias:\$($Command.Name)" -NewName (New-BackupAliasName -Name $Command.Name);
		}
	}

	end {
		Set-Alias -Name $Command.Name -Value (Get-ProxyEventFunctionName -Command $Command) -Scope 'Global';
	}
}

function New-ProxyEventFunction {
	[CmdletBinding()]
	param (
		[Parameter(Position = 0, Mandatory = $true)]
			[System.Management.Automation.CommandInfo] $Command
	)

	end {
		$FullCommandName = Get-CommandName -Command $Command;
		$MetaData = Microsoft.PowerShell.Utility\New-Object System.Management.Automation.CommandMetaData($Command);
		$CmdletBindingAttribute = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($MetaData);
		$ParamBlock = "param($([System.Management.Automation.ProxyCommand]::GetParamBlock($MetaData)))";
		$ArgsStatement = if ($Command.Definition -match '\$args') {
			'$PSBoundParameters.Add(''$args'', $args);';
		}
		$OutBufferStatement = if ($Command.Parameters.ContainsKey('OutBuffer')) {
			'$OutBuffer = $null; if ($PSBoundParameters.TryGetValue(''OutBuffer'', [ref]$OutBuffer)) { $PSBoundParameters[''OutBuffer''] = 1; }';
		}
		$DynamicParamBlock = if (($Command.Parameters.Values | Microsoft.PowerShell.Core\Where-Object { $_.IsDynamic }).Count -gt 0) {
			"dynamicparam { $([System.Management.Automation.ProxyCommand]::GetDynamicParam($MetaData)) }";
		}

		return @"
function global:$(Get-ProxyEventFunctionName -Command $Command) {
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
}

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
		Save-ScriptBlock @PsBoundParameters;
		$CommandDefinition = New-ProxyEventFunction -Command $Command;
	}

	end {
		Microsoft.PowerShell.Utility\Invoke-Expression -Command $CommandDefinition;
		New-ProxyEventAlias -Command $Command;
	}
}
