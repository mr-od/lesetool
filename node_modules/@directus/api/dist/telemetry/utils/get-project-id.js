export const getProjectId = async (db) => {
    const projectId = await db.select('project_id').from('directus_settings').first();
    return projectId?.project_id || null;
};
