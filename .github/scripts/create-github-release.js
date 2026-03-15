module.exports = async ({ github, context, releaseTag }) => {
    const requestBody = {
        owner: context.repo.owner,
        repo: context.repo.repo,
        tag_name: releaseTag,
        generate_release_notes: true,
        draft: true,
    };
    console.log(requestBody);
    await github.rest.repos.createRelease(requestBody);
};
