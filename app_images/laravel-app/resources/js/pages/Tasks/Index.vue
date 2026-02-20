<script setup lang="ts">
import { Head, useForm, router } from '@inertiajs/vue3';
import { useEcho } from '@laravel/echo-vue';
import AppLayout from '@/layouts/AppLayout.vue';
import { type BreadcrumbItem } from '@/types';
import { ref } from 'vue';

type Task = {
    id: number;
    title: string;
    description: string | null;
    status: 'pending' | 'in_progress' | 'completed';
    priority: 'low' | 'medium' | 'high';
    created_at: string;
};

type Log = {
    _id: string;
    action: string;
    model_type: string;
    model_id: string;
    user_name: string;
    created_at: string;
};

const props = defineProps<{
    tasks: Task[];
    logs: Log[];
}>();

const breadcrumbs: BreadcrumbItem[] = [
    { title: 'Tasks', href: '/tasks' },
];

const editingTask = ref<Task | null>(null);

const form = useForm({
    title: '',
    description: '',
    status: 'pending' as Task['status'],
    priority: 'medium' as Task['priority'],
});

const editForm = useForm({
    title: '',
    description: '',
    status: 'pending' as Task['status'],
    priority: 'medium' as Task['priority'],
});

function createTask() {
    form.post('/tasks', {
        preserveScroll: true,
        onSuccess: () => form.reset(),
    });
}

function startEdit(task: Task) {
    editingTask.value = task;
    editForm.title = task.title;
    editForm.description = task.description ?? '';
    editForm.status = task.status;
    editForm.priority = task.priority;
}

function updateTask() {
    if (!editingTask.value) return;
    editForm.put(`/tasks/${editingTask.value.id}`, {
        preserveScroll: true,
        onSuccess: () => {
            editingTask.value = null;
            editForm.reset();
        },
    });
}

function cancelEdit() {
    editingTask.value = null;
    editForm.reset();
}

function deleteTask(task: Task) {
    if (!confirm('Delete this task?')) return;
    router.delete(`/tasks/${task.id}`, { preserveScroll: true });
}

// Real-time updates via Reverb
useEcho('tasks', '.task.changed', () => {
    router.reload({ only: ['tasks', 'logs'], preserveScroll: true });
});

const statusColors: Record<Task['status'], string> = {
    pending: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200',
    in_progress: 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200',
    completed: 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
};

const priorityColors: Record<Task['priority'], string> = {
    low: 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200',
    medium: 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200',
    high: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200',
};
</script>

<template>
    <Head title="Tasks" />

    <AppLayout :breadcrumbs="breadcrumbs">
        <div class="flex flex-col gap-6 p-4 lg:flex-row">
            <!-- Left: Task list + create form -->
            <div class="flex-1 space-y-6">
                <!-- Create form -->
                <div class="rounded-xl border border-sidebar-border/70 p-4 dark:border-sidebar-border">
                    <h2 class="mb-3 text-lg font-semibold">New Task</h2>
                    <form @submit.prevent="createTask" class="space-y-3">
                        <div>
                            <input
                                v-model="form.title"
                                type="text"
                                placeholder="Task title"
                                class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm dark:border-gray-600 dark:bg-gray-800"
                            />
                            <p v-if="form.errors.title" class="mt-1 text-xs text-red-500">{{ form.errors.title }}</p>
                        </div>
                        <textarea
                            v-model="form.description"
                            placeholder="Description (optional)"
                            rows="2"
                            class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm dark:border-gray-600 dark:bg-gray-800"
                        />
                        <div class="flex gap-3">
                            <select v-model="form.status" class="rounded-lg border border-gray-300 px-3 py-2 text-sm dark:border-gray-600 dark:bg-gray-800">
                                <option value="pending">Pending</option>
                                <option value="in_progress">In Progress</option>
                                <option value="completed">Completed</option>
                            </select>
                            <select v-model="form.priority" class="rounded-lg border border-gray-300 px-3 py-2 text-sm dark:border-gray-600 dark:bg-gray-800">
                                <option value="low">Low</option>
                                <option value="medium">Medium</option>
                                <option value="high">High</option>
                            </select>
                            <button
                                type="submit"
                                :disabled="form.processing"
                                class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-50"
                            >
                                Add Task
                            </button>
                        </div>
                    </form>
                </div>

                <!-- Task list -->
                <div class="rounded-xl border border-sidebar-border/70 dark:border-sidebar-border">
                    <div class="border-b border-sidebar-border/70 px-4 py-3 dark:border-sidebar-border">
                        <h2 class="text-lg font-semibold">Tasks ({{ props.tasks.length }})</h2>
                    </div>

                    <div v-if="props.tasks.length === 0" class="p-8 text-center text-gray-500">
                        No tasks yet. Create one above.
                    </div>

                    <div v-else class="divide-y divide-sidebar-border/70 dark:divide-sidebar-border">
                        <div v-for="task in props.tasks" :key="task.id" class="p-4">
                            <!-- Edit mode -->
                            <form v-if="editingTask?.id === task.id" @submit.prevent="updateTask" class="space-y-3">
                                <input
                                    v-model="editForm.title"
                                    type="text"
                                    class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm dark:border-gray-600 dark:bg-gray-800"
                                />
                                <textarea
                                    v-model="editForm.description"
                                    rows="2"
                                    class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm dark:border-gray-600 dark:bg-gray-800"
                                />
                                <div class="flex gap-3">
                                    <select v-model="editForm.status" class="rounded-lg border border-gray-300 px-3 py-2 text-sm dark:border-gray-600 dark:bg-gray-800">
                                        <option value="pending">Pending</option>
                                        <option value="in_progress">In Progress</option>
                                        <option value="completed">Completed</option>
                                    </select>
                                    <select v-model="editForm.priority" class="rounded-lg border border-gray-300 px-3 py-2 text-sm dark:border-gray-600 dark:bg-gray-800">
                                        <option value="low">Low</option>
                                        <option value="medium">Medium</option>
                                        <option value="high">High</option>
                                    </select>
                                    <button type="submit" :disabled="editForm.processing" class="rounded-lg bg-green-600 px-3 py-2 text-sm text-white hover:bg-green-700">Save</button>
                                    <button type="button" @click="cancelEdit" class="rounded-lg bg-gray-500 px-3 py-2 text-sm text-white hover:bg-gray-600">Cancel</button>
                                </div>
                            </form>

                            <!-- View mode -->
                            <div v-else class="flex items-start justify-between gap-4">
                                <div class="min-w-0 flex-1">
                                    <h3 class="font-medium">{{ task.title }}</h3>
                                    <p v-if="task.description" class="mt-1 text-sm text-gray-500">{{ task.description }}</p>
                                    <div class="mt-2 flex gap-2">
                                        <span :class="statusColors[task.status]" class="rounded-full px-2 py-0.5 text-xs font-medium">
                                            {{ task.status.replace('_', ' ') }}
                                        </span>
                                        <span :class="priorityColors[task.priority]" class="rounded-full px-2 py-0.5 text-xs font-medium">
                                            {{ task.priority }}
                                        </span>
                                    </div>
                                </div>
                                <div class="flex shrink-0 gap-2">
                                    <button @click="startEdit(task)" class="rounded px-2 py-1 text-xs text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-950">Edit</button>
                                    <button @click="deleteTask(task)" class="rounded px-2 py-1 text-xs text-red-600 hover:bg-red-50 dark:hover:bg-red-950">Delete</button>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Right: Activity log from MongoDB -->
            <div class="w-full lg:w-80">
                <div class="rounded-xl border border-sidebar-border/70 dark:border-sidebar-border">
                    <div class="border-b border-sidebar-border/70 px-4 py-3 dark:border-sidebar-border">
                        <h2 class="text-lg font-semibold">Activity Log</h2>
                        <p class="text-xs text-gray-500">Stored in MongoDB, cached in Redis</p>
                    </div>

                    <div v-if="props.logs.length === 0" class="p-4 text-center text-sm text-gray-500">
                        No activity yet.
                    </div>

                    <div v-else class="divide-y divide-sidebar-border/70 dark:divide-sidebar-border">
                        <div v-for="log in props.logs" :key="log._id" class="px-4 py-3">
                            <p class="text-sm">
                                <span class="font-medium">{{ log.user_name }}</span>
                                <span class="text-gray-500"> {{ log.action }} a task</span>
                            </p>
                            <p class="mt-0.5 text-xs text-gray-400">
                                {{ new Date(log.created_at).toLocaleString() }}
                            </p>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </AppLayout>
</template>
