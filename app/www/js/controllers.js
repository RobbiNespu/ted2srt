angular.module('reted.controllers', [])

.controller('MainController', function($scope, $state) {
  var self = this;
  self.subheaderShown = false;

  self.search = function() {
    if (self.q.trim().length) {
      $state.go('search', {q: self.q})
    }
  };

  $scope.$on('$stateChangeSuccess', function() {
    if ($state.current.name !== 'search') {
      self.subheaderShown = false;
    }
  });
})

.controller('TalksCtrl', function($scope, $http, Talks) {
  $scope.model = {}
  $scope.model.hasMore = true;

  $scope.loadMore = function() {
    Talks.loadMore().then(function(data) {
      $scope.$broadcast('scroll.infiniteScrollComplete');
      $scope.talks = Talks.all();
      if (data.length < 10) {
        $scope.model.hasMore = false;
        $scope.$applyAsync();
      }
    });
  }
})

.controller('TalkCtrl', function($scope, $stateParams, $sce, API) {
  var slug = $stateParams.slug;
  var talk = null;
  API.getTalk({slug: slug}).$promise
    .then(function (data) {
      $scope.talk = data;
      $scope.talk.speaker = $scope.talk.name.split(':')[0];
      $scope.talk.title = $scope.talk.name.split(':')[1];

      $scope.getAudioUrl = function() {
        return $sce.trustAsResourceUrl('http://download.ted.com/talks/' + $scope.talk.mSlug + '.mp3');
      };
      return API.getTalkTranscript({id: $scope.talk.id}).$promise
    })
    .then(function (data) {
      $scope.talk.transcript = '<p>' + data.text.split('\n\n').join('</p><p>') + '</p>';
    });
})

.controller('SideMenuCtrl', function($scope, $state, $ionicSideMenuDelegate, API) {
  $scope.getRandomTalk = function() {
    API.getRandomTalk().$promise.then(function(data) {
      $state.go('talks', {slug: data.slug}).then(function() {
        $ionicSideMenuDelegate.toggleLeft();
      });
    });
  };
})

.controller('SearchCtrl', function($scope, $stateParams, API) {
  $scope.model = {};
  $scope.model.hasMore = false;

  API.search({q: $stateParams.q}).$promise.then(function(data) {
    $scope.talks = data;
  });
});
