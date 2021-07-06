$script:InjectBlocks = @{};
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
			if ($null -eq $script:InjectBlocks.$CommandName) {
				$script:InjectBlocks.$CommandName = @{
					'After' = @();
					'Before' = @();
				};
			}

			$MetaData = Microsoft.PowerShell.Utility\New-Object System.Management.Automation.CommandMetaData($Command);
			$ParamBlock = "param($([System.Management.Automation.ProxyCommand]::GetParamBlock($MetaData)))";
			$ParamInjectedBlock = [ScriptBlock]::Create($ParamBlock + $ScriptBlock.ToString());

			if ($Before) {
				$script:InjectBlocks.$CommandName.Before += @($ParamInjectedBlock);
			}

			if ($After) {
				$script:InjectBlocks.$CommandName.After += @($ParamInjectedBlock);
			}
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
			$FullCommandName = & $script:SafeCommands['Get-CommandName'] -Command $Command;
			$MetaData = Microsoft.PowerShell.Utility\New-Object System.Management.Automation.CommandMetaData($Command);
			$CmdletBindingAttribute = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($MetaData);
			$ParamBlock = "param($([System.Management.Automation.ProxyCommand]::GetParamBlock($MetaData)))";

			$BeforeExecuteStatement = "foreach(`$Block in `$script:InjectBlocks.'$FullCommandName'.Before) { & `$Block @PsBoundParameters; }";
			$AfterExecuteStatement = "foreach(`$Block in `$script:InjectBlocks.'$FullCommandName'.After) { & `$Block @PsBoundParameters; }";

			$BeginBlock = [System.Management.Automation.ProxyCommand]::GetBegin($MetaData) -replace '\$SteppablePipeline\.Begin', "$BeforeExecuteStatement; `$SteppablePipeline.Begin";
			$ProcessBlock = [System.Management.Automation.ProxyCommand]::GetProcess($MetaData);
			$EndBlock = [System.Management.Automation.ProxyCommand]::GetEnd($MetaData) -replace '\$SteppablePipeline\.End\(\)', "`$SteppablePipeline.End(); $AfterExecuteStatement; ";

			return @"
$CmdletBindingAttribute
$ParamBlock

$DynamicParamBlock

begin { $BeginBlock; }

process { $ProcessBlock }

end { $EndBlock }
"@;

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
		& $script:SafeCommands['Save-ScriptBlock'] @PsBoundParameters;

		$CommandDefinition = & $script:SafeCommands['New-ProxyEventFunction'] -Command $Command;
		$FunctionName = & $script:SafeCommands['Get-ProxyEventFunctionName'] -Command $Command;
		if (Microsoft.PowerShell.Management\Test-Path -Path "Function:\$FunctionName") {
			Microsoft.PowerShell.Management\Remove-Item -Path "Function:\$FunctionName";
		}
		$ScriptBlock = [ScriptBlock]::Create($CommandDefinition);
	}

	end {
		Microsoft.PowerShell.Management\New-Item -Path 'Function:\' -Name $FunctionName -Value $ScriptBlock > $null;
		Microsoft.PowerShell.Utility\Set-Alias -Name $Command.Name -Value (& $script:SafeCommands['Get-ProxyEventFunctionName'] -Command $Command);
		Microsoft.PowerShell.Core\Export-ModuleMember -Function $FunctionName;
		Microsoft.PowerShell.Core\Export-ModuleMember -Alias $Command.Name;
	}
}
