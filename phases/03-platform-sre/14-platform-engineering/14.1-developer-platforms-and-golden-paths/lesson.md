## What you will be able to do

- Explain platform engineering and the internal developer platform (IDP): what problem they solve, and how to tell if one is working.
- Treat a platform as a product: find its users, measure what it saves them, and decide what to build first.
- Design a **golden path**: the paved, supported way to build and run a service, that developers choose because it's easier.
- Build a Backstage software template that creates a production-ready service repository.
- Use a software catalog to know who owns what, and what depends on what.
- Measure a platform's success with DORA metrics and developer feedback.

## Why this matters at work

As companies grow, every team ends up solving the same problems: a pipeline, a cluster, secrets, monitoring, an on-call rota. Doing it twenty times is slow and inconsistent, and every team becomes a part-time infrastructure team. **Platform engineering** builds those pieces once, as a self-service product for the other teams. Platform engineer has become one of the most advertised infrastructure roles, Gartner expects most large engineering organisations to have a platform team, and this whole course has been building the parts of one: Terraform modules, pipelines, Kubernetes, GitOps, observability and SLOs. This module puts a product around them.

## 1. What a platform is (and isn't)

An **internal developer platform** is the set of tools, services and paved paths that let product teams build, ship and run software **without becoming infrastructure experts**. For ITL Pay's company, it's everything from Modules 7 to 13, offered as self-service:

| A team wants to... | Without a platform | With a platform |
| --- | --- | --- |
| Start a new service | Copy an old repository, fix what's out of date, ask around | A form in the developer portal: a working repository in minutes (topic 14.1) |
| Get a database | A ticket to the infrastructure team; wait days | Four lines of YAML; ready in minutes, built the approved way (topic 14.2) |
| Know they're following the rules | Find out in a security review, or an incident | Policies check every change automatically (topic 14.3) |
| Deploy | Learn the cluster, the pipeline, the cloud | Merge to `main`; GitOps does the rest (Module 12) |

What a platform is **not**: a ticket queue with a new name, a mandatory tool nobody chose, or a one-off project. Successful platforms are **products**: they have users (the developers), a roadmap, documentation and support, and they compete for adoption by being better than doing it yourself.

## 2. Platform as a product

- **Talk to your users.** Interview teams about what slows them down. The answers are usually boring and valuable: "waiting three days for a database", "nobody knows how to set up alerts".
- **Start with the thinnest useful platform**: often a template, a few Terraform modules and good documentation, not a portal.
- **Measure** what you save: time from idea to first deploy, tickets avoided, the four **DORA metrics** (deployment frequency, lead time for changes, change failure rate, time to restore service) for teams on and off the platform.
- **Make the golden path optional but attractive.** If teams are forced onto a path that doesn't fit, they work around it. If the path is clearly easier, they choose it.
- **Keep an "escape hatch"**: teams with unusual needs can step off the path, as long as they meet the same policies (topic 14.3).

## 3. Golden paths

A **golden path** (Spotify's term; Netflix says "paved road") is an opinionated, supported, end-to-end way to do something common, such as building and running an HTTP service. It encodes everything the platform team has learned:

- the repository layout, CI and image build (Module 8);
- Kubernetes manifests with the right defaults: non-root, probes with sensible timeouts, requests and limits (Modules 9 and 13);
- the GitOps application (Module 12), monitoring and an SLO document (Modules 11 and 13);
- an entry in the catalog with its owner.

Remember the readiness timeout that turned a slow database into an outage in topic 13.3: in a golden path, that lesson is fixed **once**, in the template, for every future service.

## 4. Backstage

**Backstage** (from Spotify, now a CNCF project) is the most widely used open-source developer portal. Its core features:

| Feature | What it does |
| --- | --- |
| **Software catalog** | Every service, website, library, API and team, with owners and dependencies, from `catalog-info.yaml` files in each repository |
| **Software templates** (the scaffolder) | Golden paths as forms that create repositories |
| **TechDocs** | Documentation as code (Markdown in each repository), published in the portal |
| **Plugins** | Kubernetes, Argo CD, GitHub Actions, PagerDuty, cost and hundreds more, showing each service's state in one place |

Commercial and hosted options exist too (Spotify Portal for Backstage, Roadie, Port, Cortex), and the ideas are the same.

## 5. The lab's golden path

`labs/platform/golden-path/template.yaml` is a Backstage software template for "an ITL service". The developer fills in a form (name, description, owning team, first cloud, repository); Backstage then runs three steps:

```yaml
steps:
  - id: fetch
    action: fetch:template           # copy ./skeleton, filling in ${{ values.name }} and friends
    input:
      url: ./skeleton
      copyWithoutTemplating:
        - .github/workflows/*        # GitHub Actions uses ${{ }} too: copy workflows untouched
      values:
        name: ${{ parameters.name }}
        repoOwner: ${{ (parameters.repoUrl | parseRepoUrl).owner }}
        ...
  - id: publish
    action: publish:github           # create the repository
  - id: register
    action: catalog:register         # add it to the catalog
```

The skeleton creates a repository with `catalog-info.yaml`, `deploy/` (a Kustomize base with the platform's defaults, and a dev overlay), `argocd/application.yaml` pointing at the dev cluster of the chosen cloud (topic 12.3), a CI workflow, `docs/slo.md` and a README.

The `copyWithoutTemplating` line prevents a common bug: Backstage's templates and GitHub Actions both use `${{ … }}`, so without it Backstage tries to fill in `${{ github.sha }}` and breaks the workflow.

**Testing a golden path.** A template that produces a broken repository wastes every team's first day. The course's CI renders the skeleton with sample values (`render_test.py`), then checks the result: no placeholders left, valid YAML, the Kustomize build passes kubeconform, the Argo CD application is valid, and the workflows pass actionlint. Treat templates as code, with tests.

## 6. The catalog

```yaml
# catalog-info.yaml, in every repository
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: orders-api
  annotations:
    github.com/project-slug: itlearning/orders-api
    argocd/app-name: orders-api-dev
spec:
  type: service
  lifecycle: experimental
  owner: group:payments
  system: itl-platform
```

A catalog answers questions that otherwise take a day of asking around: who owns this service, who do I page, which services call it, which use the old database version, which aren't on the golden path yet. Ownership in the catalog also connects to alerts (topic 13.2) and cost reports (Module 16).

## Practice

1. Run Backstage locally (`npx @backstage/create-app@latest`, then `yarn start`), register `labs/platform/golden-path/template.yaml`, and create a service from it into your GitHub account.
2. Run `render_test.py` and break the template on purpose: remove `copyWithoutTemplating` and use `${{ github.sha }}` in the workflow. What does the render test say?
3. Add a field to the template: "needs a database?" (yes/no). When yes, the skeleton adds a `Database` request from topic 14.2 to the dev overlay.
4. Interview two classmates about the slowest step in getting a new service running in this course. Write one page: the problem, how a platform feature would fix it, and how you'd measure the result.
5. Add `catalog-info.yaml` files for ITL Pay and your capstone repositories, with owners and a `dependsOn` relationship, and view the dependency graph in Backstage.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [What is Platform Engineering? | KodeKloud](https://www.youtube.com/watch?v=I4LBX8DYLuE) · KodeKloud · 4 min. What platform engineering is.
- [What is an Internal Developer Platform?](https://www.youtube.com/watch?v=w7hPRaPIKlU) · Platform Engineering · 4 min. What an internal developer platform is.
- [What is Backstage? (Explainer Video)](https://www.youtube.com/watch?v=85TQEpNCaU0) · Spotify R&D · 2 min. Spotify on what Backstage is.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Foundations of Platform Engineering](https://learn.microsoft.com/training/modules/foundations-platform-engineering/)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Developing a Google SRE Culture (platform and team practices)](https://www.skills.google/course_templates/95)

