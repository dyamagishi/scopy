/*
 * Copyright (c) 2026 Analog Devices Inc.
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
 */

#include <core/whatsnewoverlay.h>
#include <gui/style.h>
#include <gui/tintedoverlay.h>
#include <QPointer>
#include <QTest>

using namespace scopy;

class TST_WhatsNewOverlay : public QObject
{
	Q_OBJECT
private Q_SLOTS:
	void initTestCase() { Style::GetInstance()->init(); }
	void tintDeletedFirst()
	{
		QWidget parent;
		auto *overlay = new WhatsNewOverlay(&parent);
		auto *tint = parent.findChild<gui::TintedOverlay *>();
		QVERIFY(tint);
		delete tint;
		// Previously this called deleteLater() through a dangling pointer.
		delete overlay;
		QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
	}
	void overlayDeletedFirst()
	{
		QWidget parent;
		auto *overlay = new WhatsNewOverlay(&parent);
		QPointer<gui::TintedOverlay> tint = parent.findChild<gui::TintedOverlay *>();
		QVERIFY(tint);
		delete overlay;
		QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
		QVERIFY(tint.isNull());
	}
};

QTEST_MAIN(TST_WhatsNewOverlay)
#include "tst_whatsnewoverlay.moc"
