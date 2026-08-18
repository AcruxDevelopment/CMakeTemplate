#pragma once

#include <string>

/// @file
/// Tiny "core" module shared by every executable module in this demo.
/// Registered as a library module in source/Core/CMakeLists.txt -- see
/// that file for how its build type (STATIC/SHARED) and its fmt
/// dependency are declared.
namespace demo::core
{

	/// Builds a greeting for @p name.
	///
	/// @param name  the person (or thing) being greeted.
	/// @return a formatted greeting string, e.g. "Hello, Ale! (from demo_core)".
	std::string makeGreeting(const std::string& name);

	/// Builds a farewell for @p name.
	///
	/// @param name  the person (or thing) being bid farewell.
	/// @return a formatted farewell string, e.g. "Farewell, Ale. (from demo_core)".
	std::string makeFarewell(const std::string& name);

}
