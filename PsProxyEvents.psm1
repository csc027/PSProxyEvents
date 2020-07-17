$script:InjectBlocks = @{};

function Save-ScriptBlock {
	[CmdletBinding()]
	param (
		[Parameter(Position = 0, Mandatory = $true)]
			[String] $CommandName,

		[Parameter(Position = 1, Mandatory = $true)]
			[ScriptBlock] $Block,

		[Switch] $After,

		[Switch] $Before,

		[Switch] $Process
	)

	end {
		if ($null -eq $script:InjectBlocks.$CommandName) {
			$script:InjectBlocks.$CommandName = @{
				'After' = @();
				'Before' = @();
				'Process' = @();
			};
		}

		if ($After) {
			$script:InjectBlocks.$CommandName['After'] += $Block;
		}
		if ($Before) {
			$script:InjectBlocks.$CommandName['Before'] += $Block;
		}
		if ($Process) {
			$script:InjectBlocks.$CommandName['Process'] += $Block;
		}
	}
}

function Register-ProxyEvent {
	[CmdletBinding()]
	param (
		[System.Management.Automation.CommandInfo] $Command,
		[ScriptBlock] $Before
	)

	begin {
		$FullCommandName = if ($Command.ModuleName) {
			"$($Command.ModuleName)\$($Command.Name)";
		} else {
			$Command.Name;
		}
		Save-ScriptBlock -CommandName $FullCommandName -Block $Before -Before;
		$MetaData = New-Object System.Management.Automation.CommandMetaData($Command);
		$CmdletBindingAttribute = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($MetaData);
		$ParamBlock = [System.Management.Automation.ProxyCommand]::GetParamBlock($MetaData);
		$ArgsStatement = if ($Command.Definition -match "\`$args") {
			'$PSBoundParameters.Add(''$args'', $args);';
		}
		$OutBufferStatement = if ($Command.Parameters.ContainsKey('OutBuffer')) {
			@'
$OutBuffer = $null;
			if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$OutBuffer)) {
				$PSBoundParameters['OutBuffer'] = 1;
			}
'@;
		}
		$DynamicParamBlock = if (($Command.Parameters.Values | Microsoft.Powershell.Core\Where-Object { $_.IsDynamic }).Count -gt 0) {
			@"
dynamicparam {
		try {
			`$TargetCmd = `$ExecutionContext.InvokeCommand.GetCommand('$FullCommandName', [System.Management.Automation.CommandTypes]::$($Command.CommandType), `$PSBoundParameters);
			`$DynamicParams = @(`$TargetCmd.Parameters.GetEnumerator() | Microsoft.PowerShell.Core\Where-Object { `$_.Value.IsDynamic });
			if (`$DynamicParams.Length -gt 0) {
				`$ParamDictionary = [Management.Automation.RuntimeDefinedParameterDictionary]::new();
				foreach (`$Param in `$DynamicParams) {
					`$Param = `$Param.Value;

					if(-not `$MyInvocation.MyCommand.Parameters.ContainsKey(`$Param.Name)) {
						`$DynParam = [Management.Automation.RuntimeDefinedParameter]::new(`$Param.Name, `$Param.ParameterType, `$Param.Attributes);
						`$ParamDictionary.Add(`$Param.Name, `$DynParam);
					}
				}

				return `$ParamDictionary;
			}
		} catch {
			throw;
		}
	}
"@;
		}

		$CommandDefinition = @"
function global:Invoke-Proxy$($Command.Name -replace '-', '') {
	$CmdletBindingAttribute
	param($($ParamBlock -replace '    ', "`t`t")
	)
	$($DynamicParamBlock -replace '    ', "`t`t")
	begin {
		try {
			$OutBufferStatement
			`$WrappedCmd = `$ExecutionContext.InvokeCommand.GetCommand('$FullCommandName', [System.Management.Automation.CommandTypes]::$($Command.CommandType));
			$ArgsStatement
			`$ScriptCmd = { & `$WrappedCmd @PSBoundParameters };

			foreach(`$Block in `$script:InjectBlocks.'$FullCommandName'.Before) {
				& `$Block;
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
