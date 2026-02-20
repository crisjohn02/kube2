<?php

namespace App\Http\Controllers;

use App\Events\TaskChanged;
use App\Models\ActivityLog;
use App\Models\Task;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Inertia\Inertia;

class TaskController extends Controller
{
    public function index(Request $request)
    {
        $cacheKey = 'tasks:user:' . $request->user()->id;

        $tasks = Cache::store('redis')->remember($cacheKey, 60, function () use ($request) {
            return Task::where('user_id', $request->user()->id)
                ->orderByDesc('created_at')
                ->get();
        });

        $logs = ActivityLog::where('user_id', (string) $request->user()->id)
            ->orderByDesc('created_at')
            ->limit(20)
            ->get();

        return Inertia::render('Tasks/Index', [
            'tasks' => $tasks,
            'logs' => $logs,
        ]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'description' => 'nullable|string',
            'status' => 'in:pending,in_progress,completed',
            'priority' => 'in:low,medium,high',
        ]);

        $task = Task::create([
            ...$validated,
            'user_id' => $request->user()->id,
        ]);

        $this->clearCache($request->user()->id);
        $this->logActivity('created', $task, $request->user());

        TaskChanged::dispatch('created', $task->toArray());

        return back();
    }

    public function update(Request $request, Task $task)
    {
        $this->authorizeTask($task, $request);

        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'description' => 'nullable|string',
            'status' => 'in:pending,in_progress,completed',
            'priority' => 'in:low,medium,high',
        ]);

        $task->update($validated);

        $this->clearCache($request->user()->id);
        $this->logActivity('updated', $task, $request->user());

        TaskChanged::dispatch('updated', $task->fresh()->toArray());

        return back();
    }

    public function destroy(Request $request, Task $task)
    {
        $this->authorizeTask($task, $request);

        $taskData = $task->toArray();
        $task->delete();

        $this->clearCache($request->user()->id);
        $this->logActivity('deleted', $taskData, $request->user());

        TaskChanged::dispatch('deleted', $taskData);

        return back();
    }

    private function clearCache(int $userId): void
    {
        Cache::store('redis')->forget('tasks:user:' . $userId);
    }

    private function logActivity(string $action, $task, $user): void
    {
        $data = $task instanceof Task ? $task->toArray() : $task;

        ActivityLog::create([
            'action' => $action,
            'model_type' => 'Task',
            'model_id' => (string) ($data['id'] ?? ''),
            'user_id' => (string) $user->id,
            'user_name' => $user->name,
            'changes' => $data,
        ]);
    }

    private function authorizeTask(Task $task, Request $request): void
    {
        abort_unless($task->user_id === $request->user()->id, 403);
    }
}
