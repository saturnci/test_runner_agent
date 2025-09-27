def current_version
  "#{`git show -s --format=%ci HEAD`.strip} #{`git rev-parse HEAD`.strip}"
end