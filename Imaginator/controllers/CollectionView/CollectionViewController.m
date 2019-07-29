//
//  CollectionViewController.m
//  Imaginator
//
//  Created by Фёдор Морев on 7/28/19.
//  Copyright © 2019 Фёдор Морев. All rights reserved.
//

#import "../../utils/Colors.h"
#import "CollectionViewCell.h"
#import "CollectionViewController.h"

@interface CollectionViewController () <UICollectionViewDelegate, UICollectionViewDataSource>
@property(retain, nonatomic) NSMutableArray *dataModel;
@property(retain, nonatomic) NSOperationQueue *customQueue;

@property(assign, nonatomic) NSInteger pagesLoaded;
@end

@implementation CollectionViewController

static float const safeOffsetY = 1500;
static NSString * const reuseIdentifier = @"Cell";
static NSString * const requestUrlString = @"https://picsum.photos/v2/list";

#pragma mark - Lifecycle

- (id)init {
    self = [super init];
    if (self) {
        self.pagesLoaded = 0;
        self.dataModel = [NSMutableArray array];
        [self.dataModel addObject:[NSMutableArray array]];
        [self.dataModel addObject:[NSMutableArray array]];
        
        self.customQueue = [[[NSOperationQueue alloc] init] autorelease];
        self.customQueue.maxConcurrentOperationCount = 1;
        self.customQueue.qualityOfService = NSQualityOfServiceUserInitiated;
    }
    return self;
}

- (void)loadView {
    [super loadView];
    
    [self extendCollectionViewData];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.collectionViewLayout = [[[CollectionViewLayout alloc] init] autorelease];
    [self.collectionViewLayout updateDataModel:self.dataModel];
    
    self.collectionView = [[[UICollectionView alloc] initWithFrame:self.view.bounds
                                              collectionViewLayout:self.collectionViewLayout] autorelease];
    
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    
    self.collectionView.backgroundColor = [Colors getRandomColor];
    [self.collectionView registerClass:[CollectionViewCell class] forCellWithReuseIdentifier:reuseIdentifier];
    
    [self.view addSubview:self.collectionView];
    
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
                                              [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
                                              [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
                                              [self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
                                              [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
                                              ]];
}

#pragma mark <UICollectionViewDataSource>

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return [self.dataModel count];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self.dataModel[section] count];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    CollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:reuseIdentifier forIndexPath:indexPath];
    cell.backgroundColor = [Colors getRandomColor];
    
    NSDictionary *imageInfo = self.dataModel[indexPath.section][indexPath.item];
    
    UIImageView *imageView = [imageInfo objectForKey:@"imageView"];
    
    if ([imageView isKindOfClass:[UIImageView class]]) {
        [cell addSubview:imageView];
    } else {
        NSString *urlString = [imageInfo objectForKey:@"download_url"];
        NSURL *url = [NSURL URLWithString:urlString];
        
        [self uploadImageAtURL:url completion:^(NSData *data) {
            UIImage *image = [UIImage imageWithData:data];            
            UIImageView *imageView = [[UIImageView alloc] initWithFrame:cell.bounds];
            imageView.image = image;
            
            [imageInfo setValue:imageView forKey:@"imageView"];
            
            [cell addSubview:imageView];
        }];
    }
    
    return cell;
}

#pragma mark <UICollectionViewDelegate>


#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    
    CGSize contentSize = [self.collectionViewLayout collectionViewContentSize];
    
    if (contentSize.height < (targetContentOffset->y + safeOffsetY)) {
        [self extendCollectionViewData];
    }
}

- (void)extendCollectionViewData {
    [self.customQueue addOperationWithBlock:^{
        [self.customQueue setSuspended:YES];
        
        NSURLComponents *components = [NSURLComponents componentsWithString:requestUrlString];
        components.queryItems = @[
              [NSURLQueryItem queryItemWithName:@"limit" value:[@(50) stringValue]],
              [NSURLQueryItem queryItemWithName:@"page" value:[@(self.pagesLoaded + 1) stringValue]],
        ];
        
        NSURLSessionTask *task = [[NSURLSession sharedSession] dataTaskWithURL:components.URL completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            
            if (httpResponse.statusCode != 200) {
                NSLog(@"Response status code: %ld", httpResponse.statusCode);
                return;
            }
            
            if (error) {
                NSLog(@"Error: %@", error.localizedDescription);
                return;
            }
            
            NSError *parsingError = nil;
            
            NSArray *pictures = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&parsingError];
            
            if (parsingError) {
                NSLog(@"Error parsin JSON: %@", parsingError.localizedDescription);
                return;
            }
            
            NSMutableArray *dataModelCopy = [self.dataModel copy];
            
            for (int i = 0; i < [pictures count]; i++) {
                NSInteger section = i % [self.dataModel count];
                [dataModelCopy[section] addObject:[pictures[i] mutableCopy]];
            }
            
            self.dataModel = dataModelCopy;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self.pagesLoaded += 1;
                [self.collectionView reloadData];
                [self.collectionViewLayout invalidateLayout];
                [self.collectionViewLayout updateDataModel:self.dataModel];
                
                [self.customQueue setSuspended:NO];
            });
        }];
        
        [task resume];
    }];
}

#pragma mark - Utils

- (void)uploadImageAtURL:(NSURL *)url completion:(void(^)(NSData *))completionHandler {
    NSURLSessionTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if (httpResponse.statusCode != 200) {
            NSLog(@"Response status code: %ld", httpResponse.statusCode);
            return;
        }
        
        if (error) {
            NSLog(@"Error: %@", error.localizedDescription);
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(data);
        });
    }];
    
    [task resume];
}


@end