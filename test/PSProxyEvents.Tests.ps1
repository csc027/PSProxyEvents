BeforeAll {
	$script:ModulePath = Resolve-Path -Path ([IO.Path]::Combine($PSScriptRoot, '..', 'src', 'PSProxyEvents.psd1'));
	function script:Invoke-Function {
		return $null;
	}
	function script:Invoke-Before {
		return $null;
	}
	function script:Invoke-After {
		return $null;
	}
	function script:Invoke-BeforeAfter {
		return $null;
	}
}

Describe 'Proxy Events Tests' {
	Context 'ScriptBlock attaches and executes' {
		BeforeEach {
			Import-Module -Name $script:ModulePath -Force;
			Get-Module -Name '__DynamicModule_Proxy_*' | Remove-Module;
		}

		It 'Does not execute if not attached' {
			Mock -CommandName 'Invoke-Before' -MockWith { } -Verifiable;
			Invoke-Function;
			Should -Invoke -CommandName 'Invoke-Before' -Times 0;
		}

		It 'Attaches and executes before the chosen command' {
			Mock -CommandName 'Invoke-Before' -MockWith { } -Verifiable;
			Register-ProxyEvent -CommandName 'Invoke-Function' -ScriptBlock { Invoke-Before; } -Before;
			Invoke-Function;
			Should -Invoke -CommandName 'Invoke-Before' -Times 1;
		}

		It 'Executes multiple times before the chosen command if registered multiple times' {
			Mock -CommandName 'Invoke-Before' -MockWith { } -Verifiable;
			Register-ProxyEvent -CommandName 'Invoke-Function' -ScriptBlock { Invoke-Before; } -Before;
			Register-ProxyEvent -CommandName 'Invoke-Function' -ScriptBlock { Invoke-Before; } -Before;
			Invoke-Function;
			Should -Invoke -CommandName 'Invoke-Before' -Times 2;
		}

		It 'Attaches and executes after the chosen command' {
			Mock -CommandName 'Invoke-After' -MockWith { } -Verifiable;
			Register-ProxyEvent -CommandName 'Invoke-Function' -ScriptBlock { Invoke-After; } -After;
			Invoke-Function;
			Should -Invoke -CommandName 'Invoke-After' -Times 1;
		}

		It 'Executes multiple times after the chosen command if registered multiple times' {
			Mock -CommandName 'Invoke-After' -MockWith { } -Verifiable;
			Register-ProxyEvent -CommandName 'Invoke-Function' -ScriptBlock { Invoke-After; } -After;
			Register-ProxyEvent -CommandName 'Invoke-Function' -ScriptBlock { Invoke-After; } -After;
			Invoke-Function;
			Should -Invoke -CommandName 'Invoke-After' -Times 2;
		}

		It 'Attaches and executes before and after the chosen command' {
			Mock -CommandName 'Invoke-BeforeAfter' -MockWith { } -Verifiable;
			Register-ProxyEvent -CommandName 'Invoke-Function' -ScriptBlock { Invoke-BeforeAfter; } -Before -After;
			Invoke-Function;
			Should -Invoke -CommandName 'Invoke-BeforeAfter' -Times 2;
		}

		It 'Executes multiple times before and after the chosen command if registered multiple times' {
			Mock -CommandName 'Invoke-BeforeAfter' -MockWith { } -Verifiable;
			Register-ProxyEvent -CommandName 'Invoke-Function' -ScriptBlock { Invoke-BeforeAfter; } -Before -After;
			Register-ProxyEvent -CommandName 'Invoke-Function' -ScriptBlock { Invoke-BeforeAfter; } -Before -After;
			Invoke-Function;
			Should -Invoke -CommandName 'Invoke-BeforeAfter' -Times 2;
		}
	}

	Context 'Does not register for bad input or bad results' {
		BeforeEach {
			Import-Module -Name $script:ModulePath -Force;
		}

		It 'Does not register if the command is a native application' {
			{ Register-ProxyEvent -CommandName 'ssh' -ScriptBlock { Invoke-After; } -After } | Should -Throw;
		}

		It 'Does not register if the command name descriptor does not unambiguously refer to a single command' {
			{ Register-ProxyEvent -CommandName 'Write-*' -ScriptBlock { Invoke-After; } -After } | Should -Throw;
		}

		It 'Does not register if the command cannot be found with the supplied name' {
			{ Register-ProxyEvent -CommandName 'NonExistentCommand' -ScriptBlock { Invoke-After; } -After } | Should -Throw;
		}

		It 'Does not register if the command is from one of the dynamic modules created by the registration' {
			{ Register-ProxyEvent -Command (Get-Command -Name 'Invoke-After') -ScriptBlock { Invoke-After; } -After } | Should -Not -Throw;
			{ Register-ProxyEvent -Command (Get-Command -Name 'Invoke-After') -ScriptBlock { Invoke-After; } -After } | Should -Throw;
		}
	}
}
