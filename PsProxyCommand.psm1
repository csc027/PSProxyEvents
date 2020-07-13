function Register-ProxyCommand {
	[CmdletBinding()]
	param (
		[string] $CommandName
	)

	$Command = Get-Command -Name $CommandName;
	$CommandDefinitionName = if ($Command.ModuleName) {
		"$($Command.ModuleName)\$($Command.Name)";
	} else {
		$Command.Name;
	}
	$MetaData = New-Object System.Management.Automation.CommandMetaData($Command);
	$CmdletBindingAttribute = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($MetaData);
	$ParamBlock = [System.Management.Automation.ProxyCommand]::GetParamBlock($MetaData);
	$OutBufferStatement = if ($Command.Parameters.ContainsKey('OutBuffer')) {
		@'
$OutBuffer = $null
				if ($PSBoundParameters.TryGetValue(OutBuffer, [ref]$OutBuffer)) {
					$PSBoundParameters[OutBuffer] = 1
				}
'@;
	}
	$DynamicParamBlock = @"
    try {
        `$TargetCmd = `$ExecutionContext.InvokeCommand.GetCommand('$CommandDefinitionName', [System.Management.Automation.CommandTypes]::$($Command.CommandType), `$PSBoundParameters)
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
"@;

	$CommandDefinition = @"
	function Invoke-Proxy$($Command -replace '-', '') {
		$CmdletBindingAttribute
		param($($ParamBlock -replace "`r`n    ", "`r`n`t`t`t")
		)

		begin {
			try {
				$OutBufferStatement
				`$WrappedCmd = `$ExecutionContext.InvokeCommand.GetCommand($($CommandDefinitionName), [System.Management.Automation.CommandTypes]::$($Command.CommandType))
				`$ScriptCmd = {& `$WrappedCmd @PSBoundParameters }

				`$SteppablePipeline = `$ScriptCmd.GetSteppablePipeline(`$MyInvocation.CommandOrigin)
				`$SteppablePipeline.Begin(`$PSCmdlet)
			} catch {
				throw
			}
		}

		process {
			try {
				`$SteppablePipeline.Process(`$_)
			} catch {
				throw
			}
		}

		end {
			try {
				`$SteppablePipeline.End()
			} catch {
				throw
			}
		}
	}
"@;

	$CommandDefinition;
}
