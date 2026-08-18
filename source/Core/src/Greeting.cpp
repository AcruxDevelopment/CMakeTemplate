#include "core/Greeting.hpp"

#include <fmt/core.h>

namespace demo::core
{

	std::string makeGreeting(const std::string& name)
	{
		return fmt::format("Hello, {}! (from {})", name, MODULE_NAME);
	}

	std::string makeFarewell(const std::string& name)
	{
		return fmt::format("Farewell, {}. (from {})", name, MODULE_NAME);
	}

}
