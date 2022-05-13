{
  inputs,
  cell,
}: {
  ociNamer = oci: builtins.unsafeDiscardStringContext "${oci.imageName}:${oci.imageTag}";
  pp = v: builtins.trace (builtins.toJSON v) v;
}
