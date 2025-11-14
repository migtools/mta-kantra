FROM registry.redhat.io/ubi9/go-toolset:1.23 AS builder
COPY --chown=1001:0 . /workspace
WORKDIR /workspace

RUN CGO_ENABLED=0 GOOS=linux GOEXPERIMENT=strictfipsruntime go build -tags strictfipsruntime \
--ldflags="-X 'github.com/konveyor-ecosystem/kantra/cmd.Version=$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.RunnerImage=registry.redhat.io/mta/mta-cli-rhel9:$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.JavaBundlesLocation=/jdtls/java-analyzer-bundle/java-analyzer-bundle.core/target/java-analyzer-bundle.core.jar' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.JavaProviderImage=registry.redhat.io/mta/mta-java-external-provider-rhel9:$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.DotnetProviderImage=registry.redhat.io/mta/mta-dotnet-external-provider-rhel9:$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.GenericProviderImage=registry.redhat.io/mta/mta-generic-external-provider-rhel9:$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.RootCommandName=mta-cli' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.BuildCommit=$SOURCE_GIT_COMMIT'" \
 -a -o mta-cli main.go
RUN CGO_ENABLED=0 GOOS=darwin go build \
--ldflags="-X 'github.com/konveyor-ecosystem/kantra/cmd.Version=$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.RunnerImage=registry.redhat.io/mta/mta-cli-rhel9:$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.JavaBundlesLocation=/jdtls/java-analyzer-bundle/java-analyzer-bundle.core/target/java-analyzer-bundle.core.jar' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.JavaProviderImage=registry.redhat.io/mta/mta-java-external-provider-rhel9:$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.DotnetProviderImage=registry.redhat.io/mta/mta-dotnet-external-provider-rhel9:$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.GenericProviderImage=registry.redhat.io/mta/mta-generic-external-provider-rhel9:$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.RootCommandName=mta-cli' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.BuildCommit=$SOURCE_GIT_COMMIT'" \
 -a -o darwin-mta-cli main.go
RUN CGO_ENABLED=0 GOOS=windows go build \
--ldflags="-X 'github.com/konveyor-ecosystem/kantra/cmd.Version=$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.RunnerImage=registry.redhat.io/mta/mta-cli-rhel9:$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.JavaBundlesLocation=/jdtls/java-analyzer-bundle/java-analyzer-bundle.core/target/java-analyzer-bundle.core.jar' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.JavaProviderImage=registry.redhat.io/mta/mta-java-external-provider-rhel9:$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.DotnetProviderImage=registry.redhat.io/mta/mta-dotnet-external-provider-rhel9:$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.GenericProviderImage=registry.redhat.io/mta/mta-generic-external-provider-rhel9:$BUILD_VERSION' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.RootCommandName=mta-cli' \
-X 'github.com/konveyor-ecosystem/kantra/cmd.BuildCommit=$SOURCE_GIT_COMMIT'" \
 -a -o windows-mta-cli.exe main.go

FROM registry.redhat.io/ubi9:latest AS rulesets
COPY --chown=1001:0 . /workspace

FROM brew.registry.redhat.io/rh-osbs/mta-mta-static-report-rhel9:8.0.0 as static-report

FROM brew.registry.redhat.io/rh-osbs/mta-mta-analyzer-lsp-rhel9:8.0.0
RUN dnf -y install podman && dnf -y clean all

RUN echo mta:x:1000:0:1000 user:/home/mta:/sbin/nologin > /etc/passwd
RUN echo mta:10000:5000 > /etc/subuid
RUN echo mta:10000:5000 > /etc/subgid
RUN mkdir -p /home/mta/.config/containers/
RUN cp /etc/containers/storage.conf /home/mta/.config/containers/storage.conf
RUN sed -i "s/^driver.*/driver = \"vfs\"/g" /home/mta/.config/containers/storage.conf
RUN echo -ne '[containers]\nvolumes = ["/proc:/proc",]\ndefault_sysctls = []' > /home/mta/.config/containers/containers.conf
RUN chown -R 1000:1000 /home/mta

RUN mkdir -p /opt/rulesets /opt/rulesets/input /opt/rulesets/convert /opt/openrewrite /opt/input /opt/input/rules /opt/input/rules/custom /opt/output /tmp/source-app /tmp/source-app/input

COPY --from=builder /workspace/mta-cli /usr/local/bin/mta-cli
COPY --from=builder /workspace/darwin-mta-cli /usr/local/bin/darwin-mta-cli
COPY --from=builder /workspace/windows-mta-cli.exe /usr/local/bin/windows-mta-cli.exe
COPY --from=rulesets /workspace/hack/build/rulesets/default/generated /opt/rulesets
COPY --from=rulesets /workspace/hack/build/windup-rulesets/rules/rules-reviewed/openrewrite /opt/openrewrite
COPY --from=static-report /usr/bin/js-bundle-generator /usr/local/bin/js-bundle-generator
COPY --from=static-report /usr/local/static-report /usr/local/static-report
COPY --from=builder --chmod=755 /workspace/entrypoint.sh /usr/bin/entrypoint.sh
COPY --from=builder --chmod=755 /workspace/openrewrite_entrypoint.sh /usr/bin/openrewrite_entrypoint.sh
COPY --from=builder /workspace/LICENSE /licenses/

RUN find /opt/rulesets/azure -type f -exec sed -i '/konveyor.io\/target=azure-aks/d' {} +
RUN find /opt/rulesets/azure -type f -exec sed -i '/konveyor.io\/target=azure-container-apps/d' {} +

ENTRYPOINT ["mta-cli"]

LABEL \
        description="Migration Toolkit for Applications - CLI" \
        io.k8s.description="Migration Toolkit for Applications - CLI" \
        io.k8s.display-name="MTA - CLI" \
        io.openshift.maintainer.project="MTA" \
        io.openshift.tags="migration,modernization,mta,tackle,konveyor" \
        summary="Migration Toolkit for Applications - CLI"
