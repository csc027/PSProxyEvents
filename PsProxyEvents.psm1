function Register-ProxyEvent {
	[CmdletBinding()]
	param (
		[System.Management.Automation.CommandInfo] $Command,
		[ScriptBlock] $Before
	)

	begin {
		$CommandType = $Command.CommandType;
		$CommandName = if ($Command.ModuleName) {
			"$($Command.ModuleName)\$($Command.Name)";
		} else {
			$Command.Name;
		}
		$MetaData = New-Object System.Management.Automation.CommandMetaData($Command);
		$CmdletBindingAttribute = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($MetaData);
		$ParamBlock = [System.Management.Automation.ProxyCommand]::GetParamBlock($MetaData);
		$ArgsStatement = if ($Command.Definition -match "\`$args") {
			'$PSBoundParameters.Add(''$args'', $args)';
		}
		$OutBufferStatement = if ($Command.Parameters.ContainsKey('OutBuffer')) {
			@'
$OutBuffer = $null
			if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$OutBuffer)) {
				$PSBoundParameters['OutBuffer'] = 1
			}
'@;
		}
		$DynamicParamBlock = if (($Command.Parameters.Values | Microsoft.Powershell.Core\Where-Object { $_.IsDynamic }).Count -gt 0) {
			@"
dynamicparam {
		try {
			`$TargetCmd = `$ExecutionContext.InvokeCommand.GetCommand('$CommandName', [System.Management.Automation.CommandTypes]::$CommandType, `$PSBoundParameters)
			`$DynamicParams = @(`$TargetCmd.Parameters.GetEnumerator() | Microsoft.PowerShell.Core\Where-Object { `$_.Value.IsDynamic })
			if (`$DynamicParams.Length -gt 0) {
				`$ParamDictionary = [Management.Automation.RuntimeDefinedParameterDictionary]::new()
				foreach (`$Param in `$DynamicParams) {
					`$Param = `$Param.Value

					if(-not `$MyInvocation.MyCommand.Parameters.ContainsKey(`$Param.Name)) {
						`$DynParam = [Management.Automation.RuntimeDefinedParameter]::new(`$Param.Name, `$Param.ParameterType, `$Param.Attributes)
						`$ParamDictionary.Add(`$Param.Name, `$DynParam)
					}
				}

				return `$ParamDictionary
			}
		} catch {
			throw
		}
	}
"@;
		}
	}

	end {
		$global:Before = $Before
		$CommandDefinition = @"
function Invoke-Proxy$($Command -replace '-', '') {
	$CmdletBindingAttribute
	param($($ParamBlock -replace '    ', "`t`t")
	)
	$($DynamicParamBlock -replace '    ', "`t`t")
	begin {
		try {
			$OutBufferStatement
			`$WrappedCmd = `$ExecutionContext.InvokeCommand.GetCommand('$CommandName', [System.Management.Automation.CommandTypes]::$CommandType)
			$ArgsStatement
			`$ScriptCmd = { & `$WrappedCmd @PSBoundParameters }

			`$BeforePipeline = `$global:Before.GetSteppablePipeline(`$MyInvocation.CommandOrigin)
			`$BeforePipeline.Begin(`$PSCmdlet)

			`$SteppablePipeline = `$ScriptCmd.GetSteppablePipeline(`$MyInvocation.CommandOrigin)
			`$SteppablePipeline.Begin(`$PSCmdlet)
		} catch {
			throw
		}
	}

	process {
		try {
			`$BeforePipeline.Process(`$_)
			`$SteppablePipeline.Process(`$_)
		} catch {
			throw
		}
	}

	end {
		try {
			`$BeforePipeline.End()
			`$SteppablePipeline.End()
		} catch {
			throw
		}
	}
}
<#

.ForwardHelpTargetName $CommandName
.ForwardHelpCategory $CommandType

#>
"@;

		return $CommandDefinition;
	}
}
