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
 *
 */

#include "core/pooledcmdexecutor.h"
#include "core/command.h"

#include <QSemaphore>
#include <QTest>

#include <cerrno>

using namespace scopy;

class SlowCommand : public Command
{
	Q_OBJECT
public:
	SlowCommand(int sleepMs, void *resource = nullptr, QObject *parent = nullptr)
		: Command(resource, parent)
		, m_sleepMs(sleepMs)
	{}

	Result<void> result() const { return m_result; }

protected:
	void run() override
	{
		QThread::msleep(m_sleepMs);
		m_result = Result<void>{};
	}

private:
	int m_sleepMs;
	Result<void> m_result{Unexpected{Error{-ENODATA, QStringLiteral("command not executed")}}};
};

// Hold workers until the test releases them. This proves overlap and keeps the
// command being cancelled queued, independently of host speed and scheduling.
class GatedCommand : public Command
{
public:
	GatedCommand(QSemaphore &started, QSemaphore &release, void *resource = nullptr)
		: Command(resource)
		, m_started(started)
		, m_release(release)
	{}

protected:
	void run() override
	{
		m_started.release();
		m_release.acquire();
	}

private:
	QSemaphore &m_started;
	QSemaphore &m_release;
};

class TestPooledCmdExecutor : public QObject
{
	Q_OBJECT
private slots:
	void parallelExecution();
	void cancelByResource();
	void cancelById();
	void pendingCount();

private:
	void queuedCancellation(bool byResource);
};

void TestPooledCmdExecutor::parallelExecution()
{
	PooledCmdExecutor exec(4);
	QSemaphore started, release;
	GatedCommand c1(started, release);
	GatedCommand c2(started, release);

	auto f1 = exec.execute(&c1);
	auto f2 = exec.execute(&c2);
	const bool overlapped = started.tryAcquire(2, 5000);
	// Always unblock and join before asserting, including on failure.
	release.release(2);
	f1.waitForFinished();
	f2.waitForFinished();

	QVERIFY2(overlapped, "Both commands must start before either is released");
}

void TestPooledCmdExecutor::cancelByResource()
{
	queuedCancellation(true);
}

void TestPooledCmdExecutor::cancelById() { queuedCancellation(false); }

void TestPooledCmdExecutor::queuedCancellation(bool byResource)
{
	int resource = 0;
	PooledCmdExecutor exec(2);
	QSemaphore started, release;
	GatedCommand c1(started, release, &resource);
	GatedCommand c2(started, release, &resource);
	SlowCommand c3(0, &resource);

	auto f1 = exec.execute(&c1);
	auto f2 = exec.execute(&c2);
	const bool workersOccupied = started.tryAcquire(2, 5000);
	auto f3 = exec.execute(&c3);

	if(byResource) {
		exec.cancelByResource(&resource);
	} else {
		exec.cancelById(c3.id());
	}
	const bool cancelledWhileQueued = c3.isCancelled();
	release.release(2);

	f1.waitForFinished();
	f2.waitForFinished();

	f3.waitForFinished();
	QVERIFY2(workersOccupied, "Both workers must remain occupied while cancelling the queued command");
	QVERIFY(cancelledWhileQueued);
	QVERIFY(c3.isCancelled());
	QVERIFY2(!bool(c3.result()), "A cancelled queued command must not execute run()");
}

void TestPooledCmdExecutor::pendingCount()
{
	PooledCmdExecutor exec(4);
	QCOMPARE(exec.pendingCount(), 0);
}

QTEST_MAIN(TestPooledCmdExecutor)
#include "tst_concurrentcmdexecutor.moc"
