/*
 * Copyright (c) 2024 Analog Devices Inc.
 *
 * This file is part of Scopy
 * (see https://www.github.com/analogdevicesinc/scopy).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 *
 */

#include "qpluginloader.h"

#include <QList>
#include <QTest>

#include <pluginbase/plugin.h>
#include <component/controller.h>
#include <component/device.h>
#include <m2k/m2kcontext.h>

using namespace scopy;

class TST_M2k : public QObject
{
	Q_OBJECT
private Q_SLOTS:
	void fileExists();
	void isLibrary();
	void loaded();
	void className();
	void instanceNotNull();
	void multipleInstances();
	void qobjectcast_to_plugin();
	void clone();
	void name();
	void metadata();
	void unload();
	void controllerCompatibility();
	void unavailableControllerContext();
	void nativeContextAbi();
};

#define FILENAME SCOPY_TEST_PLUGIN_FILE

void TST_M2k::fileExists()
{
	QFile f(FILENAME);
	bool ret;
	qDebug() << QDir::currentPath();
	ret = f.open(QIODevice::ReadOnly);
	if(ret)
		f.close();
	QVERIFY(ret);
}

void TST_M2k::isLibrary() { QVERIFY(QLibrary::isLibrary(FILENAME)); }

void TST_M2k::className()
{
	QPluginLoader qp(FILENAME, this);
	QVERIFY(qp.metaData().value("className") == "M2kPlugin");
}

void TST_M2k::loaded()
{
	QPluginLoader qp(FILENAME, this);
	qp.load();
	qDebug() << (qp.errorString());
	QVERIFY(qp.isLoaded());
}

void TST_M2k::instanceNotNull()
{
	QPluginLoader qp(FILENAME, this);
	QVERIFY(qp.instance() != nullptr);
}

void TST_M2k::multipleInstances()
{
	QPluginLoader qp1(FILENAME, this);
	QPluginLoader qp2(FILENAME, this);

	QVERIFY(qp1.instance() == qp2.instance());
}

void TST_M2k::qobjectcast_to_plugin()
{
	QPluginLoader qp(FILENAME, this);
	auto instance = qobject_cast<Plugin *>(qp.instance());
	QVERIFY(instance != nullptr);
}

void TST_M2k::clone()
{
	QPluginLoader qp(FILENAME, this);

	Plugin *p1 = nullptr, *p2 = nullptr;
	auto original = qobject_cast<Plugin *>(qp.instance());
	QVERIFY(original != nullptr);
	p1 = original->clone(this);
	QVERIFY(p1 != nullptr);
	p2 = original->clone(this);
	QVERIFY(p2 != nullptr);
	QVERIFY(p1 != p2);
}

void TST_M2k::name()
{
	QPluginLoader qp(FILENAME, this);

	Plugin *p1 = nullptr, *p2 = nullptr;
	auto original = qobject_cast<Plugin *>(qp.instance());
	QVERIFY(original != nullptr);
	p1 = original->clone(this);
	qDebug() << p1->name();
}

void TST_M2k::metadata()
{
	QPluginLoader qp(FILENAME, this);

	Plugin *p1 = nullptr, *p2 = nullptr;
	auto original = qobject_cast<Plugin *>(qp.instance());
	QVERIFY(original != nullptr);
	original->initMetadata();
	p1 = original->clone(this);
	qDebug() << p1->metadata();
	QVERIFY(!p1->metadata().isEmpty());
}

void TST_M2k::unload()
{
	QPluginLoader qp(FILENAME, this);
	auto original = qobject_cast<Plugin *>(qp.instance());

	//	qp.unload();
	QVERIFY(!qp.isLoaded() == false);
}

void TST_M2k::controllerCompatibility()
{
	QPluginLoader loader(FILENAME, this);
	auto *plugin = qobject_cast<Plugin *>(loader.instance());
	QVERIFY(plugin);
	const QString uri = "test:m2k-device-controller";
	auto *tree = new component::Context();
	auto owner = component::Controller::GetInstance()->adopt(uri, tree);
	QVERIFY(owner);
	QVERIFY(!plugin->compatible(uri, "iio"));
	for(const auto &name : {"m2k-adc", "m2k-dac-a", "m2k-dac-b"}) {
		auto *device = new component::Device(tree);
		device->setName(name);
	}
	QVERIFY(plugin->compatible(uri, "iio"));
	QVERIFY(plugin->compatible(uri, "m2k"));
	QVERIFY(!plugin->compatible(uri, "other"));
	// Compatibility borrows the existing tree; it neither opens USB nor removes it.
	auto shared = component::Controller::context(uri);
	QCOMPARE(shared.get(), tree);
	owner.reset();
	QVERIFY(plugin->compatible(uri, "iio"));
	shared.reset();
	QVERIFY(!component::Controller::context(uri));
	QVERIFY(!plugin->compatible(uri, "iio"));
}

void TST_M2k::unavailableControllerContext()
{
	QPluginLoader loader(FILENAME, this);
	auto *plugin = qobject_cast<Plugin *>(loader.instance());
	QVERIFY(plugin);
	const QString uri = "test:m2k-unavailable";
	QVERIFY(!plugin->compatible(uri, "iio"));
	plugin->setParam(uri, "iio");
	QVERIFY(!plugin->onConnect());
	// A backend-neutral identity tree is never cast to a native libiio pointer.
	auto owner = component::Controller::GetInstance()->adopt(uri, new component::Context());
	QVERIFY(owner);
	QVERIFY(!plugin->onConnect());
}

void TST_M2k::nativeContextAbi()
{
	class Backend : public scopy::iio::IBackend
	{
	public:
		scopy::iio::LibiioVersion abi = scopy::iio::LibiioVersion::V0;
		scopy::iio::LibiioVersion version() const override { return abi; }
		scopy::iio::IContextOps *contextOps() override { return nullptr; }
		scopy::iio::IDeviceOps *deviceOps() override { return nullptr; }
		scopy::iio::IChannelOps *channelOps() override { return nullptr; }
		scopy::iio::IAttrOps *attrOps() override { return nullptr; }
		scopy::iio::IBufferOps *bufferOps() override { return nullptr; }
		scopy::iio::IScanOps *scanOps() override { return nullptr; }
	} backend;
	component::iio::IIOContext context;
	int token = 0;
	context.setHandle({&token});
	QVERIFY(!m2k::nativeContext(nullptr));
	QVERIFY(!m2k::nativeContext(&context));
	context.setBackend(&backend);
	const bool borrowed = m2k::nativeContext(&context) == reinterpret_cast<iio_context *>(&token);
	backend.abi = scopy::iio::LibiioVersion::V1;
	const bool rejected = m2k::nativeContext(&context) == nullptr;
	// The fake token is not a real IIO context; never pass it to a destructor.
	context.setHandle({});
	QVERIFY(borrowed);
	QVERIFY(rejected);
}

QTEST_MAIN(TST_M2k)

#include "tst_pluginloader.moc"
