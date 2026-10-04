#pragma once

#include <component/controller.h>
#include <component/device.h>
#include <component/backends/iio/iiocontext.h>
#include <iioutil/ibackend.h>

struct iio_context;

namespace scopy::m2k {

// libm2k and the existing GNU Radio instruments require the v0 ABI. Borrow
// its handle, never open a second USB connection or take ownership of it.
inline iio_context *nativeContext(component::Context *context)
{
	auto *iio = qobject_cast<component::iio::IIOContext *>(context);
	if(!iio || !iio->backend() || iio->backend()->version() != scopy::iio::LibiioVersion::V0) {
		return nullptr;
	}
	return static_cast<iio_context *>(iio->handle().ptr);
}

inline bool isM2kContext(component::Context *context)
{
	if(!context) {
		return false;
	}
	QStringList names;
	for(auto *device : context->findChildren<component::Device *>(Qt::FindDirectChildrenOnly)) {
		names.append(device->name());
	}
	return names.contains("m2k-adc") && names.contains("m2k-dac-a") && names.contains("m2k-dac-b");
}

} // namespace scopy::m2k
